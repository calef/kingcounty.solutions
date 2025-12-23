# frozen_string_literal: true

require 'json'
require 'time'
require_relative '../logging'
require_relative '../openai/chat_client'
require_relative '../front_matter/document'
require_relative '../front_matter/slug_generator'
require_relative '../support/encoding_utils'
require_relative '../content/html_normalizer'

module Mayhem
  module News
    class EventExtractor
      POSTS_DIR = '_posts'
      EVENTS_DIR = '_events'
      MAX_FILENAME_BYTES = 255
      DEFAULT_MODEL = ENV.fetch('OPENAI_EVENT_EXTRACTION_MODEL', ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini'))

      def initialize(
        posts_dir: POSTS_DIR,
        events_dir: EVENTS_DIR,
        model: DEFAULT_MODEL,
        chat_client: nil,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @posts_dir = posts_dir
        @events_dir = events_dir
        @model = model
        @logger = logger
        @chat_client = chat_client || Mayhem::OpenAI::ChatClient.new(logger: @logger)
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
        document = Mayhem::FrontMatter::Document.load(file_path, logger: @logger)
        unless document
          stats[:skipped_no_frontmatter] += 1
          return
        end

        front_matter = document.front_matter
        if front_matter['locked'] == true
          @logger.debug "Skipping #{file_path}: locked is true"
          stats[:skipped_locked] += 1
          return
        end
        if front_matter['published'] == false
          @logger.debug "Skipping #{file_path}: published is false"
          stats[:skipped_unpublished] += 1
          return
        end

        # Skip if already processed
        if front_matter['events_extracted'] == true
          stats[:skipped_already_extracted] += 1
          return
        end

        unless front_matter['summarized'] == true
          @logger.debug "Skipping #{file_path}: summarized is not true"
          stats[:skipped_unsummarized] += 1
          return
        end

        # Get post content for analysis
        post_content = document.body || ''
        post_title = front_matter['title'] || ''
        post_date = front_matter['date']
        organization_title = front_matter['source']
        source_url = front_matter['source_url']
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
          front_matter['events_extracted'] = true
          front_matter['events'] = []
          document.front_matter = front_matter
          document.save
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
            front_matter['topics'],
            front_matter['location_titles'],
            reference_time
          )
          event_ids << event_id if event_id
        end

        # Update post with event links
        front_matter['events_extracted'] = true
        front_matter['events'] = event_ids
        document.front_matter = front_matter
        document.save

        if event_ids.empty?
          stats[:no_events_found] += 1
        else
          stats[:posts_with_events] += 1
          @logger.info "Extracted #{event_ids.size} event(s) from #{file_path}"
        end
      rescue StandardError => e
        stats[:errors] += 1
        @logger.error "Error processing #{file_path}: #{e.class} - #{e.message}"
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
          { role: 'system', content: 'You are a helpful assistant that extracts event information from news articles and returns valid JSON.' },
          { role: 'user', content: prompt }
        ]

        response = @chat_client.call(messages: messages, model: @model, temperature: 0.3)
        parsed = JSON.parse(response)

        unless parsed.is_a?(Array)
          @logger.warn "Expected array response, got: #{parsed.class}"
          return []
        end

        parsed
      rescue JSON::ParserError => e
        @logger.warn "Failed to parse JSON response: #{e.message}"
        @logger.debug "Response was: #{response}"
        nil
      rescue StandardError => e
        @logger.error "Failed to extract events: #{e.message}"
        nil
      end

      def create_event(event_data, organization_title, source_url, stats, post_topics, post_location_titles, reference_time)
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
          @logger.warn "Failed to parse start_date '#{start_date_str}': #{e.message}"
          stats[:invalid_event_data] += 1
          return nil
        end

        # Skip events that have already started
        if start_time < reference_time
          @logger.debug "Skipping past event '#{title}' with start_date #{start_date_str}"
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

        # Generate filename
        date_prefix = start_time.strftime('%Y-%m-%d')
        slug = Mayhem::FrontMatter::SlugGenerator.filename_slug(
          title: title,
          link: source_url || organization_title,
          date_prefix: date_prefix,
          max_bytes: MAX_FILENAME_BYTES
        )
        filename = File.join(@events_dir, "#{date_prefix}-#{slug}.md")

        # Check if event already exists
        if File.exist?(filename)
          stats[:duplicate_events] += 1
          return File.basename(filename, '.md')
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
        front_matter['topics'] = post_topics.dup if post_topics.is_a?(Array) && post_topics.any?
        front_matter['location_titles'] = post_location_titles.dup if post_location_titles.is_a?(Array) && post_location_titles.any?

        unless description.to_s.strip.empty?
          normalized_description = Mayhem::Content::HtmlNormalizer.normalize(
            Mayhem::Support::EncodingUtils.ensure_utf8(description)
          )
          front_matter['feed_content'] = normalized_description
          front_matter['feed_content_checksum'] = Mayhem::Content::HtmlNormalizer.checksum(normalized_description)
        end

        # Create event document
        body = "\n#{description}\n"
        document = Mayhem::FrontMatter::Document.new(
          path: filename,
          front_matter: front_matter,
          body: body
        )
        document.save

        stats[:events_created] += 1
        @logger.info "Created event #{filename}"

        File.basename(filename, '.md')
      rescue StandardError => e
        @logger.error "Failed to create event: #{e.message}"
        stats[:event_creation_failed] += 1
        nil
      end

      def log_summary(stats)
        summary_fields = {
          posts_with_events: stats[:posts_with_events],
          events_created: stats[:events_created],
          no_events_found: stats[:no_events_found],
          past_events_skipped: stats[:past_events_skipped],
          skipped_no_frontmatter: stats[:skipped_no_frontmatter],
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
        @logger.info "Event extraction complete: #{summary_text}"
      end

      def reference_time_from(post_date)
        return Time.now unless post_date

        Time.parse(post_date)
      rescue StandardError => e
        @logger.warn "Failed to parse post date '#{post_date}': #{e.message}"
        Time.now
      end
    end
  end
end
