# frozen_string_literal: true

require 'ruby/openai'
require 'seldon'
require_relative '../topics/classifier'
require_relative '../locations/classifier'
require_relative '../content/article_body_extractor'
require_relative '../images/pruner'
require_relative '../feed/discovery'
require_relative 'helpers'

module Mayhem
  module Summarizer
    class Base
      include Seldon::Loggable
      include Mayhem::SummarizerHelpers

      MAX_ARTICLE_CHARS = 20_000

      def initialize(
        client: nil,
        model: default_model,
        http_client: nil,
        topic_classifier: nil,
        location_classifier: nil,
        images_pruner: nil,
        pruner: nil
      )
        @model = model
        @client = client || ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
        @http = http_client || Seldon::Support::HttpClient.new(
          cookie_jar: Seldon::Support::CookieJar.new
        )
        @images_pruner = images_pruner || Mayhem::Images::Pruner.new
        @topic_classifier = topic_classifier ||
                            Mayhem::Topics::Classifier.new(client: @client)
        @location_classifier = location_classifier ||
                               Mayhem::Locations::Classifier.new(client: @client)
        @pruner = pruner
      end

      def run
        stats = Hash.new(0)
        model_class.all.each do |record|
          process_record(record, stats)
        end
        log_summary(stats)
        stats
      end

      private

      # Template methods - subclasses must implement
      def model_class
        raise NotImplementedError, "#{self.class} must implement #model_class"
      end

      def process_record(_record, _stats)
        raise NotImplementedError, "#{self.class} must implement #process_record"
      end

      def log_summary(_stats)
        raise NotImplementedError, "#{self.class} must implement #log_summary"
      end

      def default_model
        ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini')
      end

      # Shared helpers

      def fetch_html(url)
        return nil if url.to_s.strip.empty?

        page = @http.fetch(url, accept: Mayhem::FeedDiscovery::ACCEPT_HTML)
        Seldon::Support::EncodingUtils.ensure_utf8(page[:body])
      rescue StandardError => e
        logger.warn "Error fetching #{url}: #{e.class} - #{e.message}"
        nil
      end

      def extract_text(html)
        Mayhem::Content::ArticleBodyExtractor.text_from_html(html)
      end

      def truncate_text(text, record_id, max_chars: MAX_ARTICLE_CHARS)
        return text unless text && text.length > max_chars

        logger.info "Truncating #{record_id} article text from #{text.length} to #{max_chars} chars"
        text[0, max_chars]
      end

      def classify_topics(summary_text)
        @topic_classifier.classify(summary_text)
      end

      def classify_locations(summary_text, content_title:, content_source:, content_location: nil)
        @location_classifier.classify(
          summary_text,
          content_title: content_title,
          content_location: content_location,
          content_source: content_source
        )
      end

      def call_openai(prompt, system_message, record_id, temperature:)
        attempts = 0
        while attempts < 3
          attempts += 1
          begin
            response = @client.chat(
              parameters: {
                model: @model,
                messages: [
                  { role: 'system', content: system_message },
                  { role: 'user', content: prompt }
                ],
                temperature: temperature
              }
            )
            if (error_message = response.dig('error', 'message'))
              logger.warn "OpenAI error for #{record_id}: #{error_message}"
              break
            end

            content = response.dig('choices', 0, 'message', 'content')&.strip
            return content unless content.to_s.empty?
          rescue Faraday::TooManyRequestsError
            logger.warn "Rate limited, waiting 5 seconds before retry (attempt #{attempts})"
            sleep 5
          end
        end
        nil
      end

      def needs_classification_for_record?(record, key)
        record[key].nil?
      end

      def store_source_html(record, html)
        return unless html

        source_html = Mayhem::Content::ArticleBodyExtractor.normalized_html(
          html,
          max_chars: MAX_ARTICLE_CHARS
        )
        record.original_source_html = source_html if source_html
      end
    end
  end
end
