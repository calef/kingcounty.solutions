# frozen_string_literal: true

require 'json'
require 'time'
require 'seldon'
require_relative '../openai/chat_client'
require_relative '../front_matter/slug_generator'
require_relative '../content/html_normalizer'
require_relative '../models/event'
require_relative '../models/news'

module Mayhem
  module News
    class EventExtractor
      include Seldon::Loggable

      MAX_FILENAME_BYTES = 255
      DEFAULT_MODEL = ENV.fetch('OPENAI_EVENT_EXTRACTION_MODEL', ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini'))

      def initialize(
        model: DEFAULT_MODEL,
        chat_client: nil
      )
        @model = model
        @chat_client = chat_client || Mayhem::OpenAI::ChatClient.new
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
        unless post.published?
          logger.debug "Skipping #{record_id}: published is false"
          stats[:skipped_unpublished] += 1
          return
        end

        # Skip if already processed
        if post.events_extracted?
          stats[:skipped_already_extracted] += 1
          return
        end

        unless post.summarized? == true
          logger.debug "Skipping #{record_id}: summarized is not true"
          stats[:skipped_unsummarized] += 1
          return
        end

        # Get post content for analysis
        post_content = post.body || ''
        post_title = post.title || ''
        post_date = post.date
        organization_title = post.organization_title
        source_url = post.source_url
        reference_time = reference_time_from(post_date)

        if post_content.strip.empty? && post_title.strip.empty?
          stats[:skipped_empty_content] += 1
          return
        end

        # Extract events from the post
        events = extract_events(post_title, post_content, post_date, organization_title, source_url)
        if events.nil?
          stats[:extraction_failed] += 1
          return
        end

        if events.empty?
          # Mark as extracted even if no events found
          post.events_extracted = true
          post.event_ids = []
          post.save!
          stats[:no_events_found] += 1
          return
        end

        # Create event files and track their IDs
        event_ids = []
        events.each do |event_data|
          event_id = create_event(
            event_data,
            organization_title,
            source_url,
            stats,
            post.topic_titles,
            post.location_titles,
            reference_time
          )
          event_ids << event_id if event_id
        end

        # Update post with event links
        post.events_extracted = true
        post.event_ids = event_ids
        post.save!

        if event_ids.empty?
          stats[:no_events_found] += 1
        else
          stats[:posts_with_events] += 1
          logger.info "Extracted #{event_ids.size} event(s) from #{record_id}"
        end
      rescue StandardError => e
        stats[:errors] += 1
        logger.error "Error processing #{record_id}: #{e.class} - #{e.message}"
      end

      def extract_events(title, content, post_date, organization_title, source_url)
        prompt = <<~PROMPT
          Analyze the following news article and extract any event announcements.
          An event is something that will happen at a specific time and potentially a specific place.

          Article Source: #{organization_title}
          Article URL: #{source_url}
          Article Title: #{title}
          Article Date: #{post_date}

          Article Content:
          #{content}

          Instructions:
          1. Only extract clear event announcements (with date, time, or location information)
          2. Do not extract past events (relative to the article date)
          3. Return a JSON array of events with this structure for each event:
             {
               "title": "Event title",
               "start_date": "ISO 8601 datetime (e.g., 2025-12-09T18:00:00-08:00)",
               "end_date": "ISO 8601 datetime or null",
               "location": "Location description or empty string",
               "description": "Brief description of the event"
             }
          4. If NO events are found, return an empty array: []
          5. Return ONLY the JSON array, no other text or explanation.
          6. Use Pacific timezone (America/Los_Angeles) for dates if timezone is not specified.
        PROMPT

        messages = [
          { role: 'system',
            content: 'You are a helpful assistant that extracts event information from news articles and returns valid JSON.' },
          { role: 'user', content: prompt }
        ]

        response = @chat_client.call(messages: messages, model: @model, temperature: 0.3)
        parsed = JSON.parse(response)

        unless parsed.is_a?(Array)
          logger.warn "Expected array response, got: #{parsed.class}"
          return []
        end

        parsed
      rescue JSON::ParserError => e
        logger.warn "Failed to parse JSON response: #{e.message}"
        logger.debug "Response was: #{response}"
        nil
      rescue StandardError => e
        logger.error "Failed to extract events: #{e.message}"
        nil
      end

      def create_event(event_data, organization_title, source_url, stats, post_topic_titles, post_location_titles, reference_time)
        title = event_data['title']
        start_date_str = event_data['start_date']
        end_date_str = event_data['end_date']
        location = event_data['location'] || ''
        description = event_data['description'] || ''

        unless title && start_date_str
          stats[:invalid_event_data] += 1
          return nil
        end

        begin
          start_time = Time.parse(start_date_str)
        rescue StandardError => e
          logger.warn "Failed to parse start_date '#{start_date_str}': #{e.message}"
          stats[:invalid_event_data] += 1
          return nil
        end

        # Skip events that have already started
        if start_time < reference_time
          logger.debug "Skipping past event '#{title}' with start_date #{start_date_str}"
          stats[:past_events_skipped] += 1
          return nil
        end

        end_time = nil
        if end_date_str
          begin
            end_time = Time.parse(end_date_str)
          rescue StandardError
            # End time is optional
          end
        end

        # Generate event_id to check for duplicates
        date_prefix = start_time.strftime('%Y-%m-%d')
        slug = Mayhem::FrontMatter::SlugGenerator.filename_slug(
          title: title,
          link: source_url || organization_title,
          date_prefix: date_prefix,
          max_bytes: MAX_FILENAME_BYTES
        )
        event_id = "_events/#{date_prefix}-#{slug}.md"

        # Check if event already exists
        begin
          Mayhem::Models::Event.find(event_id)
          stats[:duplicate_events] += 1
          return event_id
        rescue FMRepo::NotFound
          # Event doesn't exist, continue to create
        end

        # Create event frontmatter
        front_matter = {
          'title' => title,
          'organization_title' => organization_title,
          'start_date' => start_time.iso8601,
          'location' => location,
          'source_url' => source_url,
          'generated_from_post' => true
        }
        front_matter['end_date'] = end_time.iso8601 if end_time
        front_matter['topic_titles'] = post_topic_titles.dup if post_topic_titles.is_a?(Array) && post_topic_titles.any?
        front_matter['location_titles'] = post_location_titles.dup if post_location_titles.is_a?(Array) && post_location_titles.any?

        unless description.to_s.strip.empty?
          normalized_description = Mayhem::Content::HtmlNormalizer.normalize(
            Seldon::Support::EncodingUtils.ensure_utf8(description)
          )
          front_matter['feed_content'] = normalized_description
          front_matter['feed_content_checksum'] = Mayhem::Content::HtmlNormalizer.checksum(normalized_description)
        end

        # Create event using Models
        body_content = "\n#{description}\n"
        new_event = Mayhem::Models::Event.create!(
          front_matter,
          body: body_content
        )

        stats[:events_created] += 1
        logger.info "Created event #{new_event.id || new_event.path}"

        new_event.id || event_id
      rescue StandardError => e
        logger.error "Failed to create event: #{e.message}"
        stats[:event_creation_failed] += 1
        nil
      end

      def log_summary(stats)
        summary_fields = {
          posts_with_events: stats[:posts_with_events],
          events_created: stats[:events_created],
          no_events_found: stats[:no_events_found],
          past_events_skipped: stats[:past_events_skipped],
          skipped_unpublished: stats[:skipped_unpublished],
          skipped_unsummarized: stats[:skipped_unsummarized],
          skipped_locked: stats[:skipped_locked],
          skipped_already_extracted: stats[:skipped_already_extracted],
          skipped_empty_content: stats[:skipped_empty_content],
          duplicate_events: stats[:duplicate_events],
          invalid_event_data: stats[:invalid_event_data],
          extraction_failed: stats[:extraction_failed],
          event_creation_failed: stats[:event_creation_failed],
          errors: stats[:errors]
        }
        summary_text = summary_fields.map { |key, value| "#{key}=#{value}" }.join(', ')
        logger.info "Event extraction complete: #{summary_text}"
      end

      def reference_time_from(post_date)
        return Time.now unless post_date

        Time.parse(post_date)
      rescue StandardError => e
        logger.warn "Failed to parse post date '#{post_date}': #{e.message}"
        Time.now
      end
    end
  end
end
