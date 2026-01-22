# frozen_string_literal: true

require 'json'
require 'seldon'

require_relative '../openai/chat_client'
require_relative '../models/topic'

module Mayhem
  module Topics
    class Classifier
      include Seldon::Loggable

      DEFAULT_MODEL = ENV.fetch('OPENAI_TOPIC_MODEL', ENV.fetch('OPENAI_MODEL', 'gpt-5.1'))
      DEFAULT_TEMPERATURE = 0.2

      def initialize(
        model: DEFAULT_MODEL,
        topic_repo: nil,
        topic_model: Mayhem::Models::Topic,
        client: nil,
        chat_client: nil
      )
        @model = model
        @topic_repo = topic_repo
        @topic_model = topic_model
        @chat_client = chat_client || Mayhem::OpenAI::ChatClient.new(client: client)
      end

      def classify(text)
        return [] if text.to_s.strip.empty?

        catalog = @topic_model.relation(repo: @topic_repo).to_a
        return [] if catalog.empty?

        allowed_titles = catalog.map(&:title)
        catalog_lines = catalog.map do |topic|
          summary = topic.body
          "- #{topic.title}: #{summary&.empty? ? 'No summary provided.' : summary}"
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
            logger.warn 'Rate limited during topic classification, waiting 5 seconds ' \
                        "before retry (attempt #{attempts})"
            sleep 5
          rescue JSON::ParserError
            logger.warn "Non-JSON response while classifying topics: #{response.inspect}"
          end
        end

        []
      rescue StandardError => e
        logger.warn "Topic classification failed: #{e.message}"
        []
      end
    end
  end
end
