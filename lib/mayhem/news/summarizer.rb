# frozen_string_literal: true

require 'json'
require 'ruby/openai'
require 'seldon'
require_relative '../topics/classifier'
require_relative '../locations/classifier'
require_relative '../news/pruner'
require_relative '../images/pruner'
require_relative '../feed/discovery'
require_relative '../summarizer/helpers'
require_relative '../content/article_body_extractor'
require_relative '../models/news'

module Mayhem
  module News
    class PostSummarizer
      include Seldon::Loggable
      include Mayhem::SummarizerHelpers

      IMAGE_ASSETS_DIR = File.join('assets', 'images')
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
        assets_dir: IMAGE_ASSETS_DIR,
        client: nil,
        http_client: nil,
        topic_classifier: nil,
        location_classifier: nil,
        news_pruner: nil,
        images_pruner: nil
      )
        @client = client || ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
        @http = http_client || Seldon::Support::HttpClient.new
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
                           assets_dir: assets_dir
                         )
        @news_pruner = news_pruner ||
                       Mayhem::News::Pruner.new(
                         images_pruner: @images_pruner
                       )
      end

      def run
        stats = Hash.new(0)
        Mayhem::Models::News.all.each do |post|
          process_post(post, stats)
        end
        log_summary(stats)
        stats
      end

      private

      def process_post(post, stats)
        record_id = post.id || post.path || 'unknown-post'

        if post.locked? == true
          logger.debug "Skipping #{record_id}: locked is true"
          stats[:skipped_locked] += 1
          return
        end
        if post['published'] == false
          logger.debug "Skipping #{record_id}: published is false"
          stats[:skipped_unpublished] += 1
          # For unpublished posts during backfill, just set location_titles to empty array
          # without making API calls to classify locations
          needs_location_titles = post['location_titles'].nil?
          if needs_location_titles && post.summarized? == true
            post['location_titles'] = []
            post.save!
            @news_pruner.unpublish(post)
            stats[:locations_backfilled] += 1
            logger.info "Set location_titles to [] and cleaned up images for unpublished #{record_id}"
          end
          return
        end

        existing_summary = post.body&.strip
        needs_summary = post.summarized? != true
        needs_topic_titles = needs_classification_for_record?(post, 'topic_titles')
        needs_location_titles = needs_classification_for_record?(post, 'location_titles')
        summary_missing = post.summarized? == true && existing_summary.to_s.empty?
        return unless needs_summary || needs_topic_titles || needs_location_titles || summary_missing

        source_url = post.source_url
        if needs_summary && source_url.nil?
          logger.warn "Skipping #{record_id}: no source_url"
          stats[:skipped_missing_source] += 1
          return
        end

        feed_html = post.feed_content
        fallback_text = Mayhem::Content::ArticleBodyExtractor.text_from_html(feed_html)
        html_for_summary = nil
        article_text = nil

        if needs_summary
          scraped_html = fetch_article_html(source_url)
          scraped_text = Mayhem::Content::ArticleBodyExtractor.text_from_html(scraped_html)
          if prefer_fallback_body?(scraped_text, fallback_text)
            article_text = fallback_text
            html_for_summary = feed_html
            logger.debug "Using fallback body for #{record_id}"
          else
            article_text = scraped_text
            html_for_summary = scraped_html
          end
          article_text ||= fallback_text
          html_for_summary ||= feed_html
          article_text = article_text&.strip
          if article_text.to_s.empty?
            logger.warn "Skipping #{record_id}: no usable content to summarize"
            stats[:failed_summary] += 1
            mark_unsummarizable(post, record_id)
            return
          end
          if article_text.length > MAX_ARTICLE_CHARS
            logger.info "Truncating #{record_id} article text from #{article_text.length} to #{MAX_ARTICLE_CHARS} chars"
            article_text = article_text[0, MAX_ARTICLE_CHARS]
          end

          if (source_html = Mayhem::Content::ArticleBodyExtractor.sanitized_html(html_for_summary, max_chars: MAX_ARTICLE_CHARS))
            post['original_source_html'] = source_html
          end
          summary_text = generate_summary(article_text, source_url, record_id, stats)
          return if needs_summary && (summary_text.nil? || summary_text.empty?)

          post['summarized'] = true
        else
          summary_text = post.body&.strip
        end

        summary_text ||= post.body&.strip || ''
        summary_missing = summary_text.to_s.strip.empty?

        if needs_topic_titles
          classified_topic_titles = @topic_classifier.classify(summary_text)
          post['topic_titles'] = classified_topic_titles
          if classified_topic_titles.empty?
            logger.info "No topics matched for #{record_id}"
            stats[:missing_topics] += 1
          end
        end

        if needs_location_titles
          classified_locations = @location_classifier.classify(
            summary_text,
            content_title: post['title'],
            content_source: post['organization_title']
          )
          post['location_titles'] = classified_locations
          if classified_locations.empty?
            logger.info "No locations matched for #{record_id}"
            stats[:missing_locations] += 1
          end
        end

        # Set published to false if either topic titles or location titles are empty
        should_unpublish = summary_missing ||
                           (needs_topic_titles && Array(post['topic_titles']).empty?) ||
                           (needs_location_titles && Array(post['location_titles']).empty?)

        post.body = summary_text
        post.save!

        @news_pruner.unpublish(post) if should_unpublish

        stats[:updated] += 1
        logger.info "Updated #{record_id}"
      rescue StandardError => e
        stats[:errors] += 1
        logger.error "Error processing #{record_id}: #{e.class} - #{e.message}"
      end

      def generate_summary(article_text, source_url, record_id, stats)
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
              logger.warn "OpenAI error for #{record_id}: #{error_message}"
              break
            end

            summary = response.dig('choices', 0, 'message', 'content')&.strip
            return summary unless summary.to_s.empty?
          rescue Faraday::TooManyRequestsError
            logger.warn "Rate limited, waiting 5 seconds before retry (attempt #{attempts})"
            sleep 5
          end
        end

        logger.warn "Skipped #{record_id}: could not summarize"
        stats[:failed_summary] += 1
        nil
      end

      def fetch_article_html(url)
        return nil unless url

        page = @http.fetch(url, accept: Mayhem::FeedDiscovery::ACCEPT_HTML)
        Seldon::Support::EncodingUtils.ensure_utf8(page[:body])
      rescue StandardError => e
        logger.warn "Error fetching #{url}: #{e.class} - #{e.message}"
        nil
      end

      def log_summary(stats)
        summary_fields = {
          updated: stats[:updated],
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
      def mark_unsummarizable(post, _record_id)
        post['summarized'] = true
        post['topic_titles'] = []
        post['location_titles'] = []
        post.save!
        @news_pruner.unpublish(post)
      end

      def needs_classification_for_record?(record, key)
        record[key].nil?
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
