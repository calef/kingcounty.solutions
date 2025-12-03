# frozen_string_literal: true

require 'json'
require 'ruby/openai'

require_relative '../logging'
require_relative '../support/front_matter_document'

module Mayhem
  module News
    class TopicClassifier
      TOPIC_DIR = '_topics'
      DEFAULT_MODEL = ENV.fetch('OPENAI_TOPIC_MODEL', ENV.fetch('OPENAI_MODEL', 'gpt-5.1'))
      DEFAULT_TEMPERATURE = 0.2

      def initialize(topic_dir: TOPIC_DIR, model: DEFAULT_MODEL, client: nil, logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
        @topic_dir = topic_dir
        @model = model
        @logger = logger
        @client = client || OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
      end

      def classify(text)
        return [] if text.to_s.strip.empty?

        catalog = load_topic_catalog
        return [] if catalog.empty?

        allowed_titles = catalog.map { |topic| topic['title'] }
        catalog_lines = catalog.map do |topic|
          summary = topic['summary']
          "- #{topic['title']}: #{summary&.empty? ? 'No summary provided.' : summary}"
        end

        prompt = <<~PROMPT
          You are selecting topics for a local news post.

          Topic catalog:
          #{catalog_lines.join("\n")}

          News content:
          #{text.strip}

          Return a JSON array of topic titles from the catalog above that clearly apply to this news post.
          Only use titles from the catalog; do not invent new topics.
          Exclude topics that are only weakly related or unclear.
        PROMPT

        attempts = 0
        while attempts < 3
          attempts += 1
          begin
            response = call_llm(
              [
                { role: 'system', content: 'You are a precise classification assistant who responds with JSON arrays.' },
                { role: 'user', content: prompt }
              ],
              temperature: DEFAULT_TEMPERATURE
            )
            cleaned = strip_markdown_code_fence(response)
            parsed = JSON.parse(cleaned)
            selections = Array(parsed).map(&:to_s).select { |title| allowed_titles.include?(title) }.uniq
            return selections
          rescue Faraday::TooManyRequestsError
            @logger.warn "Rate limited during topic classification, waiting 5 seconds before retry (attempt #{attempts})"
            sleep 5
          rescue JSON::ParserError
            @logger.warn "Non-JSON response while classifying topics: #{response.inspect}"
          end
        end

        []
      rescue StandardError => e
        @logger.warn "Topic classification failed: #{e.message}"
        []
      end

      private

      def load_topic_catalog
        Dir.glob(File.join(@topic_dir, '*.md')).filter_map do |path|
          doc = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless doc

          title = doc.front_matter['title']
          summary = doc.body.to_s.strip
          next unless title

          { 'title' => title, 'summary' => summary }
        end
      end

      def call_llm(messages, temperature:)
        response = @client.chat(
          parameters: {
            model: @model,
            temperature: temperature,
            messages: messages
          }
        )
        if (error_message = response.dig('error', 'message'))
          raise "LLM request failed: #{error_message}"
        end

        content = response.dig('choices', 0, 'message', 'content')
        raise 'LLM response missing content' unless content

        content
      end

      def strip_markdown_code_fence(text)
        stripped = text.to_s.strip
        return stripped unless stripped.start_with?('```')

        lines = stripped.lines
        lines.shift
        lines.pop if lines.last&.strip == '```'
        lines.join.strip
      end
    end
  end
end
