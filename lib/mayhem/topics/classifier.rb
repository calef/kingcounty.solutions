# frozen_string_literal: true

require 'json'

require_relative '../logging'
require_relative '../openai/chat_client'
require_relative '../models/topic'

module Mayhem
  module Topics
    class Classifier
      DEFAULT_MODEL = ENV.fetch('OPENAI_TOPIC_MODEL', ENV.fetch('OPENAI_MODEL', 'gpt-5.1'))
      DEFAULT_TEMPERATURE = 0.2

      def initialize(topic_repo: nil, topic_model: Mayhem::Models::Topic, model: DEFAULT_MODEL, client: nil,
                     chat_client: nil, logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
        @topic_repo = topic_repo
        @topic_model = topic_model
        @model = model
        @logger = logger
        @chat_client = chat_client || Mayhem::OpenAI::ChatClient.new(client: client, logger: @logger)
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
            response = @chat_client.call(
              messages: [
                { role: 'system',
                  content: 'You are a precise classification assistant who responds with JSON arrays.' },
                { role: 'user', content: prompt }
              ],
              model: @model,
              temperature: DEFAULT_TEMPERATURE
            )
            parsed = JSON.parse(response)
            selections = Array(parsed).map(&:to_s).select { |title| allowed_titles.include?(title) }.uniq
            return selections
          rescue Faraday::TooManyRequestsError
            @logger.warn 'Rate limited during topic classification, waiting 5 seconds ' \
                         "before retry (attempt #{attempts})"
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
        relation = @topic_model.relation(repo: @topic_repo)
        relation.to_a.filter_map do |topic|
          title = topic.title
          next unless title

          summary = topic.body.to_s.strip
          { 'title' => title, 'summary' => summary }
        end
      end
    end
  end
end
