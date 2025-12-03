# frozen_string_literal: true

require 'ruby/openai'
require_relative '../logging'

module Mayhem
  module OpenAI
    class ChatClient
      DEFAULT_TEMPERATURE = 0.3

      def initialize(client: nil, logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
        @client = client || ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
        @logger = logger
      end

      def call(messages:, model:, temperature: DEFAULT_TEMPERATURE)
        response = @client.chat(
          parameters: {
            model: model,
            temperature: temperature,
            messages: messages
          }
        )
        if (error_message = response.dig('error', 'message'))
          raise "LLM request failed: #{error_message}"
        end

        content = response.dig('choices', 0, 'message', 'content')
        raise 'LLM response missing content' unless content

        sanitize(content)
      end

      private

      def sanitize(text)
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
