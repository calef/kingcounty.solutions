# frozen_string_literal: true

require 'ruby/openai'
require 'pathname'
require 'seldon'
require_relative '../topics/classifier'
require_relative '../locations/classifier'
require_relative '../content/article_body_extractor'
require_relative '../events/pruner'
require_relative '../images/pruner'
require_relative '../feed/discovery'
require_relative '../summarizer/helpers'
require_relative '../models/event'
require_relative '../models/news'

module Mayhem
  module Events
    class EventSummarizer
      include Seldon::Loggable
      include Mayhem::SummarizerHelpers

      IMAGE_ASSETS_DIR = File.join('assets', 'images')
      MAX_ARTICLE_CHARS = 20_000
      DEFAULT_MODEL = ENV.fetch('OPENAI_EVENT_MODEL', ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini'))

      def initialize(
        assets_dir: IMAGE_ASSETS_DIR,
        client: nil,
        model: DEFAULT_MODEL,
        http_client: nil,
        topic_classifier: nil,
        location_classifier: nil,
        event_pruner: nil,
        images_pruner: nil
      )
        @posts_dir = Mayhem::Models::News.collection_dir
        @model = model
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
        @event_pruner = event_pruner ||
                        Mayhem::Events::Pruner.new(
                          images_pruner: @images_pruner
                        )
      end

      def run
        stats = Hash.new(0)
        Mayhem::Models::Event.all.each do |event|
          process_event(event, stats)
        end
        log_summary(stats)
        stats
      end

      private

      def process_event(event, stats)
        unless event
          stats[:skipped_no_frontmatter] += 1
          return
        end

        record_id = event.id || event.path || 'unknown-event'
        if event.locked? == true
          logger.debug "Skipping #{record_id}: locked is true"
          stats[:skipped_locked] += 1
          return
        end
        if event.summarized? == true
          stats[:skipped_already_summarized] += 1
          needs_location_titles = event['location_titles'].nil?
          if needs_location_titles
            summary_text = event.body&.strip || ''
            classified_locations = @location_classifier.classify(
              summary_text,
              content_title: event['title'],
              content_location: event['location'],
              content_source: event['organization_title']
            )
            event['location_titles'] = classified_locations

            if classified_locations.empty?
              @event_pruner.unpublish(event)
              logger.info "No locations matched for #{record_id}, marking as unpublished and cleaning up images"
            else
              event.save!
            end

            stats[:locations_backfilled] += 1
            logger.info "Backfilled locations for #{record_id}"
          end
          return
        end

        needs_summary = event.summarized? != true
        needs_topic_titles = needs_classification_for_record?(event, 'topic_titles')
        needs_location_titles = needs_classification_for_record?(event, 'location_titles')
        return unless needs_summary || needs_topic_titles || needs_location_titles

        generated_from_post = event.generated_from_post? == true
        source_url = event.source_url
        feed_html = event.feed_content
        fallback_text = Mayhem::Content::ArticleBodyExtractor.text_from_html(feed_html)
        article_text = nil
        html_for_summary = nil

        summary_text = nil
        if needs_summary
          if generated_from_post
            if feed_html.to_s.strip.empty?
              logger.warn "Skipping #{record_id}: generated from post but has no body"
              stats[:skipped_missing_body] += 1
              return
            end
            article_text = fallback_text
            html_for_summary = feed_html
          elsif source_url.to_s.strip.empty?
            logger.warn "Skipping #{record_id}: no source_url"
            stats[:skipped_missing_source] += 1
            return
          else
            scraped_html = fetch_event_html(source_url)
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
          end

          article_text = article_text&.strip
          if article_text.to_s.empty?
            handle_unusable_content(event, record_id, stats, generated_from_post: generated_from_post)
            return
          end

          if article_text.length > MAX_ARTICLE_CHARS
            logger.info "Truncating #{record_id} article text from #{article_text.length} to #{MAX_ARTICLE_CHARS} chars"
            article_text = article_text[0, MAX_ARTICLE_CHARS]
          end

          if (source_html = Mayhem::Content::ArticleBodyExtractor.sanitized_html(html_for_summary, max_chars: MAX_ARTICLE_CHARS))
            event['original_source_html'] = source_html
          end

          summary_text = generate_summary(article_text, event, record_id, generated_from_post: generated_from_post)
          if summary_text.to_s.strip.empty?
            stats[:failed_summary] += 1
            return
          end
          event['summarized'] = true
          event.body = summary_text
        else
          summary_text = event.body&.strip
        end

        summary_text ||= ''

        if needs_topic_titles
          classified_topic_titles = @topic_classifier.classify(summary_text)
          event['topic_titles'] = classified_topic_titles
          if classified_topic_titles.empty?
            logger.info "No topics matched for #{record_id}"
            stats[:missing_topics] += 1
          end
        end

        if needs_location_titles
          classified_locations = @location_classifier.classify(
            summary_text,
            content_title: event['title'],
            content_location: event['location'],
            content_source: event['organization_title']
          )
          event['location_titles'] = classified_locations
          if classified_locations.empty?
            logger.info "No locations matched for #{record_id}"
            stats[:missing_locations] += 1
          end
        end

        # Set published to false if either topic titles or location titles are empty
        should_unpublish = (needs_topic_titles && Array(event['topic_titles']).empty?) ||
                           (needs_location_titles && Array(event['location_titles']).empty?)

        if should_unpublish
          @event_pruner.unpublish(event)
          if generated_from_post
            removed_refs = remove_event_references(event)
            stats[:events_unlinked] += removed_refs if removed_refs&.positive?
          end
        else
          event.save!
        end

        stats[:updated] += 1
        logger.info "Updated #{record_id}"
      rescue StandardError => e
        stats[:errors] += 1
        logger.error "Error processing #{record_id}: #{e.class} - #{e.message}"
      end

      def generate_summary(article_text, event, record_id, generated_from_post: false)
        location = event['location'].to_s.strip
        location_instruction = if location.empty?
                                 'Mention the start date (and end date if it differs) in natural language.'
                               else
                                 'Mention the start date (and end date if it differs) plus the location in natural language.'
                               end

        if generated_from_post
          prompt = <<~PROMPT
            Refine the following event description for a community calendar in 150 words or less using Markdown paragraphs, following The Associated Press Stylebook.

            Event title: #{event['title']}
            Starts at: #{event['start_date']}
            Location: #{location.empty? ? 'Not specified' : location}

            Current event description:
            #{article_text}

            In the refined description:
              1. Focus on what attendees can expect or do at this specific event.
              2. #{location_instruction}
              3. Do not include links, lists, headings, or code fences.
              4. Always write in English even if the source content is in another language.
              5. Write directly about the event itself, not about the news article that announced it.
              6. Expand on the description if needed to make it more informative and engaging.
          PROMPT
        else
          prompt = <<~PROMPT
            Summarize the following event for a community calendar in 150 words or less using Markdown paragraphs, following The Associated Press Stylebook.

            Event title: #{event['title']}
            Starts at: #{event['start_date']}
            Location: #{location.empty? ? 'Not specified' : location}

            In the summary:
              1. Emphasize what attendees can expect or do at the event.
              2. #{location_instruction}
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

        logger.warn "Skipped #{record_id}: could not summarize event"
        nil
      end

      def remove_event_references(event)
        identifiers = event_identifiers(event)
        updated_posts = 0
        Mayhem::Models::News.relation.to_a.each do |post|
          event_ids = post['event_ids']
          next unless event_ids.is_a?(Array)
          next unless event_ids.any? { |id| identifiers.include?(id.to_s) }

          updated_events = event_ids.reject { |id| identifiers.include?(id.to_s) }
          post['event_ids'] = updated_events.empty? ? [] : updated_events
          post.save!
          updated_posts += 1
          logger.info "Removed event #{identifiers.first} from #{post.path || post.id}"
        end
        updated_posts
      end

      def fetch_event_html(url)
        return nil if url.to_s.strip.empty?

        page = @http.fetch(url, accept: Mayhem::FeedDiscovery::ACCEPT_HTML)
        Seldon::Support::EncodingUtils.ensure_utf8(page[:body])
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

      def handle_unusable_content(event, record_id, stats, generated_from_post:)
        logger.warn "Skipping #{record_id}: no usable content to summarize"
        stats[:failed_summary] += 1

        event['topic_titles'] = [] if event['topic_titles'].nil?
        event['location_titles'] = [] if event['location_titles'].nil?
        event['published'] = false
        event['summarized'] = true
        event.body = ''
        @event_pruner.unpublish(event)

        return unless generated_from_post

        removed_refs = remove_event_references(event)
        stats[:events_unlinked] += removed_refs if removed_refs&.positive?
      end

      def needs_classification_for_record?(record, key)
        value = record[key]
        value.nil?
      end

      def event_identifiers(event)
        identifiers = []
        identifiers << event.id.to_s if event.respond_to?(:id) && event.id
        if event.respond_to?(:path) && event.path
          identifiers << event.path.to_s
          identifiers << event_id_for_path(event.path)
        end

        expanded = identifiers.compact.map(&:to_s).uniq
        additional_identifiers = []
        expanded.each do |identifier|
          next if identifier.empty?

          if identifier.end_with?('.md') && !identifier.include?('/')
            additional_identifiers << File.join('_events', identifier)
          elsif !identifier.include?('/')
            additional_identifiers << File.join('_events', "#{identifier}.md")
          end

          begin
            additional_identifiers << event_id_for_path(identifier)
          rescue StandardError
            nil
          end
        end

        (expanded + additional_identifiers).compact.map(&:to_s).uniq
      end

      def event_id_for_path(path)
        root = Pathname.new(events_dir).parent
        Pathname.new(path).relative_path_from(root).to_s
      end
    end
  end
end
