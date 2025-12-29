# frozen_string_literal: true

require 'ruby/openai'
require_relative '../logging'
require_relative '../topics/classifier'
require_relative '../locations/classifier'
require_relative '../content/article_body_extractor'
require_relative '../events/pruner'
require_relative '../images/pruner'
require_relative '../front_matter/document'
require_relative '../support/http_client'
require_relative '../feed/discovery'
require_relative '../support/encoding_utils'
require_relative '../summarizer/helpers'
require_relative '../models/news'

# TODO: replace use of Mayhem::FrontMatter::Document with respective Mayhem::Models::* classes

module Mayhem
  module Events
    class EventSummarizer
      include Mayhem::Loggable
      include Mayhem::SummarizerHelpers

      EVENTS_DIR = '_events'
      IMAGES_DIR = '_images'
      IMAGE_ASSETS_DIR = File.join('assets', 'images')
      MAX_ARTICLE_CHARS = 20_000
      DEFAULT_MODEL = ENV.fetch('OPENAI_EVENT_MODEL', ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini'))

      def initialize(
        events_dir: EVENTS_DIR,
        images_dir: IMAGES_DIR,
        assets_dir: IMAGE_ASSETS_DIR,
        client: nil,
        model: DEFAULT_MODEL,
        http_client: nil,
        topic_classifier: nil,
        location_classifier: nil,
        event_pruner: nil,
        images_pruner: nil
      )
        @events_dir = events_dir
        @model = model
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
                           events_dir: events_dir,
                           images_dir: images_dir,
                           assets_dir: assets_dir
                         )
        @event_pruner = event_pruner ||
                        Mayhem::Events::Pruner.new(
                          events_dir: events_dir,
                          images_pruner: @images_pruner
                        )
      end

      def run
        stats = Hash.new(0)
        Dir.glob(File.join(@events_dir, '*.md')).each do |file_path|
          process_event(file_path, stats)
        end
        log_summary(stats)
        stats
      end

      private

      def process_event(file_path, stats)
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
        if front_matter['summarized'] == true
          stats[:skipped_already_summarized] += 1
          needs_location_titles = !front_matter.key?('location_titles')
          if needs_location_titles
            summary_text = document.body&.strip || ''
            classified_locations = @location_classifier.classify(
              summary_text,
              content_title: front_matter['title'],
              content_location: front_matter['location'],
              content_source: front_matter['organization_title']
            )
            front_matter['location_titles'] = classified_locations
            document.front_matter = front_matter
            document.save

            if classified_locations.empty?
              @event_pruner.unpublish(file_path, document)
              logger.info "No locations matched for #{file_path}, marking as unpublished and cleaning up images"
            end

            stats[:locations_backfilled] += 1
            logger.info "Backfilled locations for #{file_path}"
          end
          return
        end

        needs_summary = front_matter['summarized'] != true
        needs_topic_titles = needs_classification?(front_matter, 'topic_titles')
        needs_location_titles = needs_classification?(front_matter, 'location_titles')
        return unless needs_summary || needs_topic_titles || needs_location_titles

        generated_from_post = front_matter['generated_from_post'] == true
        source_url = front_matter['source_url']
        feed_html = front_matter['feed_content']
        fallback_text = Mayhem::Content::ArticleBodyExtractor.text_from_html(feed_html)
        article_text = nil
        html_for_summary = nil

        summary_text = nil
        if needs_summary
          if generated_from_post
            if feed_html.to_s.strip.empty?
              logger.warn "Skipping #{file_path}: generated from post but has no body"
              stats[:skipped_missing_body] += 1
              return
            end
            article_text = fallback_text
            html_for_summary = feed_html
          elsif source_url.to_s.strip.empty?
            logger.warn "Skipping #{file_path}: no source_url"
            stats[:skipped_missing_source] += 1
            return
          else
            scraped_html = fetch_event_html(source_url)
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
          end

          article_text = article_text&.strip
          if article_text.to_s.empty?
            handle_unusable_content(document, front_matter, file_path, stats, generated_from_post: generated_from_post)
            return
          end

          if article_text.length > MAX_ARTICLE_CHARS
            logger.info "Truncating #{file_path} article text from #{article_text.length} to #{MAX_ARTICLE_CHARS} chars"
            article_text = article_text[0, MAX_ARTICLE_CHARS]
          end

          if (source_html = Mayhem::Content::ArticleBodyExtractor.sanitized_html(html_for_summary, max_chars: MAX_ARTICLE_CHARS))
            front_matter['original_source_html'] = source_html
          end

          summary_text = generate_summary(article_text, front_matter, file_path, generated_from_post: generated_from_post)
          if summary_text.to_s.strip.empty?
            stats[:failed_summary] += 1
            return
          end
          front_matter['summarized'] = true
          document.body = summary_text
        else
          summary_text = document.body&.strip
        end

        summary_text ||= ''

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
            content_location: front_matter['location'],
            content_source: front_matter['organization_title']
          )
          front_matter['location_titles'] = classified_locations
          if classified_locations.empty?
            logger.info "No locations matched for #{file_path}"
            stats[:missing_locations] += 1
          end
        end

        # Set published to false if either topic titles or location titles are empty
        should_unpublish = (needs_topic_titles && Array(front_matter['topic_titles']).empty?) ||
                           (needs_location_titles && Array(front_matter['location_titles']).empty?)

        document.front_matter = front_matter
        document.save

        if should_unpublish
          @event_pruner.unpublish(file_path, document)
          if generated_from_post
            event_id = File.basename(file_path)
            removed_refs = remove_event_references(event_id)
            stats[:events_unlinked] += removed_refs if removed_refs&.positive?
          end
        end

        stats[:updated] += 1
        logger.info "Updated #{file_path}"
      rescue StandardError => e
        stats[:errors] += 1
        logger.error "Error processing #{file_path}: #{e.class} - #{e.message}"
      end

      def generate_summary(article_text, front_matter, file_path, generated_from_post: false)
        if generated_from_post
          prompt = <<~PROMPT
            Refine the following event description for a community calendar in 150 words or less using Markdown paragraphs, following The Associated Press Stylebook.

            Event title: #{front_matter['title']}
            Starts at: #{front_matter['start_date']}
            Location: #{front_matter['location']}

            Current event description:
            #{article_text}

            In the refined description:
              1. Focus on what attendees can expect or do at this specific event.
              2. Mention the start date (and end date if it differs) plus the location in natural language.
              3. Do not include links, lists, headings, or code fences.
              4. Always write in English even if the source content is in another language.
              5. Write directly about the event itself, not about the news article that announced it.
              6. Expand on the description if needed to make it more informative and engaging.
          PROMPT
        else
          prompt = <<~PROMPT
            Summarize the following event for a community calendar in 150 words or less using Markdown paragraphs, following The Associated Press Stylebook.

            Event title: #{front_matter['title']}
            Starts at: #{front_matter['start_date']}
            Location: #{front_matter['location']}

            In the summary:
              1. Emphasize what attendees can expect or do at the event.
              2. Mention the start date (and end date if it differs) plus the location in natural language.
              3. Do not include links, lists, headings, or code fences.
              4. Always write in English even if the source content is in another language.
              5. Do not describe the summarization process—write directly about the event.

            EVENT DETAILS:
            #{article_text}
          PROMPT
        end

        attempts = 0
        while attempts < 3
          attempts += 1
          begin
            response = @client.chat(
              parameters: {
                model: @model,
                messages: [
                  { role: 'system',
                    content: 'You write concise community event descriptions following The Associated Press Stylebook.' },
                  { role: 'user', content: prompt }
                ],
                temperature: 0.5
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

        logger.warn "Skipped #{file_path}: could not summarize event"
        nil
      end

      def remove_event_references(event_id)
        updated_posts = 0
        Dir.glob(File.join(@posts_dir, '*.md')).each do |post_path|
          document = Mayhem::FrontMatter::Document.load(post_path)
          next unless document

          front_matter = document.front_matter
          event_ids = front_matter['event_ids']
          next unless event_ids.is_a?(Array)
          next unless event_ids.include?(event_id)

          updated_events = event_ids.reject { |id| id == event_id }
          front_matter['event_ids'] = updated_events.empty? ? [] : updated_events
          document.front_matter = front_matter
          document.save
          updated_posts += 1
          logger.info "Removed event #{event_id} from #{post_path}"
        end
        updated_posts
      end

      def fetch_event_html(url)
        return nil if url.to_s.strip.empty?

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
          skipped_locked: stats[:skipped_locked],
          skipped_already_summarized: stats[:skipped_already_summarized],
          skipped_missing_source: stats[:skipped_missing_source],
          skipped_missing_body: stats[:skipped_missing_body],
          failed_summary: stats[:failed_summary],
          missing_topics: stats[:missing_topics],
          missing_locations: stats[:missing_locations],
          locations_backfilled: stats[:locations_backfilled],
          events_unlinked: stats[:events_unlinked],
          errors: stats[:errors]
        }
        summary_text = summary_fields.map { |key, value| "#{key}=#{value}" }.join(', ')
        logger.info "Event summarization complete: #{summary_text}"
      end

      def prefer_fallback_body?(scraped_text, fallback_body)
        return false if fallback_body.to_s.strip.empty?

        cleaned = scraped_text.to_s.strip
        cleaned.empty?
      end

      def handle_unusable_content(document, front_matter, file_path, stats, generated_from_post:)
        logger.warn "Skipping #{file_path}: no usable content to summarize"
        stats[:failed_summary] += 1

        front_matter['topic_titles'] ||= []
        front_matter['location_titles'] ||= []
        front_matter['published'] = false
        front_matter['summarized'] = true
        document.front_matter = front_matter
        document.body = ''
        document.save
        @event_pruner.unpublish(file_path, document)

        return unless generated_from_post

        event_slug = File.basename(file_path, '.md')
        removed_refs = remove_event_references(event_slug)
        stats[:events_unlinked] += removed_refs if removed_refs&.positive?
      end
    end
  end
end
