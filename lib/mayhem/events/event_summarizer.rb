# frozen_string_literal: true

require 'nokogiri'
require 'ruby/openai'
require_relative '../logging'
require_relative '../news/topic_classifier'
require_relative '../support/front_matter_document'
require_relative '../support/http_client'
require_relative '../feed_discovery'

module Mayhem
  module Events
    class EventSummarizer
      EVENTS_DIR = '_events'
      MAX_ARTICLE_CHARS = 20_000
      DEFAULT_MODEL = ENV.fetch('OPENAI_EVENT_MODEL', ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini'))
      TOPIC_DIR = '_topics'

      def initialize(
        events_dir: EVENTS_DIR,
        topic_dir: TOPIC_DIR,
        client: nil,
        model: DEFAULT_MODEL,
        http_client: nil,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        topic_classifier: nil
      )
        @events_dir = events_dir
        @logger = logger
        @model = model
        @client = client || ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
        @http = http_client || Mayhem::Support::HttpClient.new(logger: @logger)
        @topic_classifier = topic_classifier ||
                            Mayhem::News::TopicClassifier.new(
                              topic_dir: topic_dir,
                              client: @client,
                              logger: @logger
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
        document = Mayhem::Support::FrontMatterDocument.load(file_path, logger: @logger)
        unless document
          stats[:skipped_no_frontmatter] += 1
          return
        end

        front_matter = document.front_matter
        needs_summary = front_matter['summarized'] != true
        needs_topics = Array(front_matter['topics']).empty?
        return unless needs_summary || needs_topics

        source_url = front_matter['source_url']
        article_text = nil
        if needs_summary
          if source_url.to_s.strip.empty?
            @logger.warn "Skipping #{file_path}: no source_url"
            stats[:skipped_missing_source] += 1
            return unless needs_topics
          else
            article_text = fetch_article_text(source_url)
          end
          article_text = document.body.to_s.strip if article_text.to_s.strip.empty?
          if article_text && article_text.length > MAX_ARTICLE_CHARS
            @logger.info "Truncating #{file_path} article text from #{article_text.length} to #{MAX_ARTICLE_CHARS} chars"
            article_text = article_text[0, MAX_ARTICLE_CHARS]
          end
        end
        article_text ||= document.body.to_s.strip

        summary_text = if needs_summary
                         summary = generate_summary(article_text, front_matter, file_path)
                         if summary.to_s.strip.empty?
                           stats[:failed_summary] += 1
                           return
                         end
                         summary
                       else
                         document.body&.strip
                       end
        summary_text ||= ''

        if needs_summary
          front_matter['original_markdown_body'] ||= document.body&.strip
          front_matter['summarized'] = true
          document.body = summary_text
        end

        if needs_topics
          classified_topics = @topic_classifier.classify(summary_text)
          front_matter['topics'] = classified_topics
          if classified_topics.empty?
            @logger.info "No topics matched for #{file_path}"
            stats[:missing_topics] += 1
          end
        end

        front_matter['published'] = false if needs_topics && Array(front_matter['topics']).empty?

        document.front_matter = front_matter
        document.save
        stats[:updated] += 1
        @logger.info "Updated #{file_path}"
      rescue StandardError => e
        stats[:errors] += 1
        @logger.error "Error processing #{file_path}: #{e.class} - #{e.message}"
      end

      def generate_summary(article_text, front_matter, file_path)
        prompt = <<~PROMPT
          Summarize the following event for a community calendar in 150 words or less using Markdown paragraphs.

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

        attempts = 0
        while attempts < 3
          attempts += 1
          begin
            response = @client.chat(
              parameters: {
                model: @model,
                messages: [
                  { role: 'system', content: 'You write concise community event descriptions.' },
                  { role: 'user', content: prompt }
                ],
                temperature: 0.5
              }
            )
            if (error_message = response.dig('error', 'message'))
              @logger.warn "OpenAI error for #{file_path}: #{error_message}"
              break
            end

            summary = response.dig('choices', 0, 'message', 'content')&.strip
            return summary unless summary.to_s.empty?
          rescue Faraday::TooManyRequestsError
            @logger.warn "Rate limited, waiting 5 seconds before retry (attempt #{attempts})"
            sleep 5
          end
        end

        @logger.warn "Skipped #{file_path}: could not summarize event"
        nil
      end

      def fetch_article_text(url)
        return '' if url.to_s.strip.empty?

        page = @http.fetch(url, accept: Mayhem::FeedDiscovery::ACCEPT_HTML, max_bytes: MAX_ARTICLE_CHARS)
        doc = Nokogiri::HTML(page[:body])
        doc.search('script, style, nav, header, footer, noscript, iframe').remove
        doc.css('article, main, body').text.strip.gsub(/\s+/, ' ')
      rescue StandardError => e
        @logger.warn "Error fetching #{url}: #{e.class} - #{e.message}"
        ''
      end

      def log_summary(stats)
        summary_fields = {
          updated: stats[:updated],
          skipped_no_frontmatter: stats[:skipped_no_frontmatter],
          skipped_missing_source: stats[:skipped_missing_source],
          failed_summary: stats[:failed_summary],
          missing_topics: stats[:missing_topics],
          errors: stats[:errors]
        }
        summary_text = summary_fields.map { |key, value| "#{key}=#{value}" }.join(', ')
        @logger.info "Event summarization complete: #{summary_text}"
      end
    end
  end
end
