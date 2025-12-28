# frozen_string_literal: true

require 'json'
require 'ruby/openai'
require_relative '../logging'
require_relative '../topics/classifier'
require_relative '../locations/classifier'
require_relative '../news/pruner'
require_relative '../images/pruner'
require_relative '../front_matter/document'
require_relative '../support/http_client'
require_relative '../feed/discovery'
require_relative '../summarizer/helpers'
require_relative '../content/article_body_extractor'

# TODO: replace use of Mayhem::FrontMatter::Document with respective Mayhem::Models::* classes

module Mayhem
  module News
    class PostSummarizer
      include Mayhem::Loggable
      include Mayhem::SummarizerHelpers

      POSTS_DIR = '_posts'
      IMAGES_DIR = '_images'
      IMAGE_ASSETS_DIR = File.join('assets', 'images')
      EVENTS_DIR = '_events'
      MAX_ARTICLE_CHARS = 20_000
      MIN_SCRAPED_LENGTH = 400
      BOILERPLATE_PATTERNS = [
        /advanced features such as clipboard/i,
        /official federal government website/i,
        /before sharing sensitive information/i,
        /security of the connection/i,
        /you have safely connected to/i
      ].freeze
      DEFAULT_MODEL = ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini')
      DEFAULT_TOPIC_MODEL = ENV.fetch('OPENAI_TOPIC_MODEL', DEFAULT_MODEL)

      def initialize(
        posts_dir: POSTS_DIR,
        images_dir: IMAGES_DIR,
        assets_dir: IMAGE_ASSETS_DIR,
        events_dir: EVENTS_DIR,
        client: nil,
        http_client: nil,
        topic_classifier: nil,
        location_classifier: nil,
        news_pruner: nil,
        images_pruner: nil
      )
        @posts_dir = posts_dir
        @client = client || ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
        @http = http_client || Mayhem::Support::HttpClient.new
        @topic_classifier = topic_classifier ||
                            Mayhem::Topics::Classifier.new(
                              client: @client
                            )
        @location_classifier = location_classifier ||
                               Mayhem::Locations::Classifier.new(
                                 client: @client
                               )
        @images_pruner = images_pruner ||
                         Mayhem::Images::Pruner.new(
                           posts_dir: posts_dir,
                           events_dir: events_dir,
                           images_dir: images_dir,
                           assets_dir: assets_dir
                         )
        @news_pruner = news_pruner ||
                       Mayhem::News::Pruner.new(
                         posts_dir: posts_dir,
                         images_pruner: @images_pruner
                       )
      end

      def run
        stats = Hash.new(0)
        Dir.glob(File.join(@posts_dir, '*.md')).each do |file_path|
          process_post(file_path, stats)
        end
        log_summary(stats)
        stats
      end

      private

      def process_post(file_path, stats)
        document = Mayhem::FrontMatter::Document.load(file_path)
        unless document
          stats[:skipped_no_frontmatter] += 1
          return
        end

        front_matter = document.front_matter
        if front_matter['locked'] == true
          logger.debug "Skipping #{file_path}: locked is true"
          stats[:skipped_locked] += 1
          return
        end
        if front_matter['published'] == false
          logger.debug "Skipping #{file_path}: published is false"
          stats[:skipped_unpublished] += 1
          # For unpublished posts during backfill, just set location_titles to empty array
          # without making API calls to classify locations
          needs_location_titles = !front_matter.key?('location_titles')
          if needs_location_titles && front_matter['summarized'] == true
            front_matter['location_titles'] = []
            @news_pruner.unpublish(file_path, document)
            stats[:locations_backfilled] += 1
            logger.info "Set location_titles to [] and cleaned up images for unpublished #{file_path}"
          end
          return
        end

        existing_summary = document.body&.strip
        needs_summary = front_matter['summarized'] != true
        needs_topic_titles = needs_classification?(front_matter, 'topic_titles')
        needs_location_titles = needs_classification?(front_matter, 'location_titles')
        summary_missing = front_matter['summarized'] == true && existing_summary.to_s.empty?
        return unless needs_summary || needs_topic_titles || needs_location_titles || summary_missing

        source_url = front_matter['source_url']
        if needs_summary && source_url.nil?
          logger.warn "Skipping #{file_path}: no source_url"
          stats[:skipped_missing_source] += 1
          return
        end

        feed_html = front_matter['feed_content']
        fallback_text = Mayhem::Content::ArticleBodyExtractor.text_from_html(feed_html)
        html_for_summary = nil
        article_text = nil

        if needs_summary
          scraped_html = fetch_article_html(source_url)
          scraped_text = Mayhem::Content::ArticleBodyExtractor.text_from_html(scraped_html)
          if prefer_fallback_body?(scraped_text, fallback_text)
            article_text = fallback_text
            html_for_summary = feed_html
            logger.debug "Using fallback body for #{file_path}"
          else
            article_text = scraped_text
            html_for_summary = scraped_html
          end
          article_text ||= fallback_text
          html_for_summary ||= feed_html
          article_text = article_text&.strip
          if article_text.to_s.empty?
            logger.warn "Skipping #{file_path}: no usable content to summarize"
            stats[:failed_summary] += 1
            mark_unsummarizable(document, front_matter)
            return
          end
          if article_text.length > MAX_ARTICLE_CHARS
            logger.info "Truncating #{file_path} article text from #{article_text.length} to #{MAX_ARTICLE_CHARS} chars"
            article_text = article_text[0, MAX_ARTICLE_CHARS]
          end

          if (source_html = Mayhem::Content::ArticleBodyExtractor.sanitized_html(html_for_summary, max_chars: MAX_ARTICLE_CHARS))
            front_matter['original_source_html'] = source_html
          end
          summary_text = generate_summary(article_text, source_url, file_path,
                                          stats)
          return if needs_summary && (summary_text.nil? || summary_text.empty?)

          front_matter['summarized'] = true
        else
          summary_text = document.body&.strip
        end

        summary_text ||= document.body&.strip || ''
        summary_missing = summary_text.to_s.strip.empty?

        if needs_topic_titles
          classified_topic_titles = @topic_classifier.classify(summary_text)
          front_matter['topic_titles'] = classified_topic_titles
          if classified_topic_titles.empty?
            logger.info "No topics matched for #{file_path}"
            stats[:missing_topics] += 1
          end
        end

        if needs_location_titles
          classified_locations = @location_classifier.classify(
            summary_text,
            content_title: front_matter['title'],
            content_source: front_matter['organization_title']
          )
          front_matter['location_titles'] = classified_locations
          if classified_locations.empty?
            logger.info "No locations matched for #{file_path}"
            stats[:missing_locations] += 1
          end
        end

        # Set published to false if either topic titles or location titles are empty
        should_unpublish = summary_missing ||
                           (needs_topic_titles && Array(front_matter['topic_titles']).empty?) ||
                           (needs_location_titles && Array(front_matter['location_titles']).empty?)

        document.front_matter = front_matter
        document.body = summary_text
        document.save

        @news_pruner.unpublish(file_path, document) if should_unpublish

        stats[:updated] += 1
        logger.info "Updated #{file_path}"
      rescue StandardError => e
        stats[:errors] += 1
        logger.error "Error processing #{file_path}: #{e.class} - #{e.message}"
      end

      def generate_summary(article_text, source_url, file_path, stats)
        prompt = <<~PROMPT
          Summarize the following article in 200 words or less in Markdown format for a news aggregator blog, adhering to The Associated Press Stylebook.

          Article URL: #{source_url}

          In the summary:
            1. Do not include a link back to the source URL.
            2. Do not include an image if one is referenced in the text.
            3. Do not include any commentary or explanation about this process.
            4. Focus only on the provided text (do not mention if the content was truncated).
            5. Always write the summary in English, even if the source material uses another language.
            6. Do not include any headings or code blocks.
            7. Do not write that the article says something, just write what the article says. Do not write "The article discusses..." or "The article outlines...". Do write a summary of the article content.
            8. Use clear language no more complex than a 10th grade reading level.

          ARTICLE CONTENT:
          #{article_text}
        PROMPT

        attempts = 0
        while attempts < 3
          attempts += 1
          begin
            response = @client.chat(
              parameters: {
                model: DEFAULT_MODEL,
                messages: [
                  { role: 'system',
                    content: 'You are a helpful assistant who writes summaries that follow The Associated Press Stylebook.' },
                  { role: 'user', content: prompt }
                ],
                temperature: 0.7
              }
            )
            if (error_message = response.dig('error', 'message'))
              logger.warn "OpenAI error for #{file_path}: #{error_message}"
              break
            end

            summary = response.dig('choices', 0, 'message', 'content')&.strip
            return summary unless summary.to_s.empty?
          rescue Faraday::TooManyRequestsError
            logger.warn "Rate limited, waiting 5 seconds before retry (attempt #{attempts})"
            sleep 5
          end
        end

        logger.warn "Skipped #{file_path}: could not summarize"
        stats[:failed_summary] += 1
        nil
      end

      def fetch_article_html(url)
        return nil unless url

        page = @http.fetch(url, accept: Mayhem::FeedDiscovery::ACCEPT_HTML)
        Mayhem::Support::EncodingUtils.ensure_utf8(page[:body])
      rescue StandardError => e
        logger.warn "Error fetching #{url}: #{e.class} - #{e.message}"
        nil
      end

      def log_summary(stats)
        summary_fields = {
          updated: stats[:updated],
          skipped_no_frontmatter: stats[:skipped_no_frontmatter],
          skipped_unpublished: stats[:skipped_unpublished],
          skipped_locked: stats[:skipped_locked],
          skipped_missing_source: stats[:skipped_missing_source],
          failed_summary: stats[:failed_summary],
          missing_topics: stats[:missing_topics],
          missing_locations: stats[:missing_locations],
          locations_backfilled: stats[:locations_backfilled],
          errors: stats[:errors]
        }
        summary_text = summary_fields.map { |key, value| "#{key}=#{value}" }.join(', ')
        logger.info "News summarization complete: #{summary_text}"
      end

      # Ensure required fields are present even when we cannot summarize due to missing content
      def mark_unsummarizable(document, front_matter)
        front_matter['summarized'] = true
        front_matter['topic_titles'] = []
        front_matter['location_titles'] = []
        document.front_matter = front_matter
        document.save
        @news_pruner.unpublish(document.path, document)
      end

      def prefer_fallback_body?(scraped_text, fallback_body)
        return false if fallback_body.to_s.empty?

        cleaned = scraped_text.to_s.strip
        return true if cleaned.empty?
        return true if BOILERPLATE_PATTERNS.any? { |pattern| cleaned.match?(pattern) }

        cleaned.length < MIN_SCRAPED_LENGTH && fallback_body.length > cleaned.length
      end
    end
  end
end
