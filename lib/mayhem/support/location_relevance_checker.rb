# frozen_string_literal: true

require 'ruby/openai'
require 'yaml'
require_relative '../logging'

module Mayhem
  module Support
    class LocationRelevanceChecker
      DEFAULT_MODEL = ENV['OPENAI_LOCATION_MODEL'] || ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini')
      MAX_RETRY_ATTEMPTS = 3
      DEFAULT_CONFIG_PATH = File.expand_path('../../../_config.yml', __dir__)

      def initialize(
        client: nil,
        model: DEFAULT_MODEL,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        config_path: DEFAULT_CONFIG_PATH
      )
        @client = client || build_client
        @model = model
        @logger = logger
        @config = load_config(config_path)
      end

      def relevant?(title:, content:, location: nil)
        return true unless enabled?
        return true unless @client

        prompt = build_prompt(title: title, content: content, location: location)

        attempts = 0
        while attempts < MAX_RETRY_ATTEMPTS
          attempts += 1
          begin
            response = @client.chat(
              parameters: {
                model: @model,
                messages: [
                  {
                    role: 'system',
                    content: 'You are a location relevance analyzer. Answer only "yes" or "no".'
                  },
                  { role: 'user', content: prompt }
                ],
                temperature: 0.1
              }
            )

            if (error_message = response.dig('error', 'message'))
              @logger.warn "OpenAI error during location check: #{error_message}"
              return true
            end

            answer = response.dig('choices', 0, 'message', 'content')&.strip&.downcase
            return answer == 'yes'
          rescue Faraday::TooManyRequestsError
            @logger.warn "Rate limited during location check, waiting 5 seconds before retry (attempt #{attempts})"
            sleep 5
          rescue StandardError => e
            @logger.warn "Error checking location relevance: #{e.message}"
            return true
          end
        end

        @logger.warn 'Failed to check location relevance after retries, defaulting to relevant'
        true
      end

      # Alias for backward compatibility
      def relevant_to_king_county?(title:, content:, location: nil)
        relevant?(title: title, content: content, location: location)
      end

      def configured_locations
        locations = @config.dig('location_relevance', 'locations') || []
        return locations unless locations.empty?

        # Fallback to hardcoded King County if no config
        [{
          'name' => 'King County, Washington',
          'description' => 'King County, Washington includes cities such as Seattle, Bellevue, Renton, ' \
                           'Kent, Auburn, Federal Way, and many others in the greater Seattle metropolitan area.'
        }]
      end

      private

      def enabled?
        @config.dig('location_relevance', 'enabled') != false
      end

      def load_config(config_path)
        return {} unless config_path && File.exist?(config_path)

        YAML.safe_load_file(config_path) || {}
      rescue StandardError => e
        @logger.warn "Failed to load config from #{config_path}: #{e.message}"
        {}
      end

      def build_client
        return nil unless ENV['OPENAI_API_KEY']

        ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
      rescue StandardError => e
        @logger.error "Failed to initialize OpenAI client: #{e.class}"
        nil
      end

      def build_prompt(title:, content:, location:)
        location_info = location.to_s.strip.empty? ? '' : "\nLocation: #{location}"

        locations = configured_locations

        location_descriptions = locations.map do |loc|
          "- #{loc['name']}: #{loc['description']}"
        end.join("\n")

        location_names = locations.map { |loc| loc['name'] }.join(', ')

        <<~PROMPT
          Determine if the following content is more likely than not to be relevant to an audience in one of these locations:

          #{location_descriptions}

          Consider content relevant if:
          - It explicitly mentions #{location_names} or cities/areas within these locations
          - It discusses state or regional policies, programs, or services that would apply to residents in these locations
          - It is about local community resources, events, or services in these areas
          - The location field indicates one of these locations

          Consider content NOT relevant if:
          - It is clearly about another location outside these areas
          - It discusses local matters from outside these locations
          - It is about policies or services that do not apply to these regions

          When in doubt, err on the side of relevance.

          Title: #{title}#{location_info}

          Content:
          #{truncate_content(content)}

          Answer only "yes" or "no" - is this content relevant to the specified audience?
        PROMPT
      end

      def truncate_content(content, max_chars: 3000)
        text = content.to_s.strip
        return text if text.length <= max_chars

        truncated = text[0, max_chars]
        last_space = truncated.rindex(' ')
        last_space ? truncated[0, last_space] : truncated
      end
    end
  end
end
