# frozen_string_literal: true

require 'ruby/openai'
require_relative '../logging'

module Mayhem
  module Support
    class LocationRelevanceChecker
      DEFAULT_MODEL = ENV['OPENAI_LOCATION_MODEL'] || ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini')
      MAX_RETRY_ATTEMPTS = 3

      def initialize(
        client: nil,
        model: DEFAULT_MODEL,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @client = client || build_client
        @model = model
        @logger = logger
      end

      def relevant_to_king_county?(title:, content:, location: nil)
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

      private

      def build_client
        api_key = ENV.fetch('OPENAI_API_KEY', nil)
        return nil unless api_key && !api_key.empty?

        ::OpenAI::Client.new(access_token: api_key)
      rescue StandardError
        @logger.warn 'Failed to initialize OpenAI client'
        nil
      end

      def build_prompt(title:, content:, location:)
        location_info = location.to_s.strip.empty? ? '' : "\nLocation: #{location}"

        <<~PROMPT
          Determine if the following content is more likely than not to be relevant to an audience in King County, Washington.

          King County, Washington includes cities such as Seattle, Bellevue, Renton, Kent, Auburn, Federal Way, and many others in the greater Seattle metropolitan area.

          Consider content relevant if:
          - It explicitly mentions King County, Seattle, or other cities within King County
          - It discusses Washington state policies, programs, or services that would apply to King County residents
          - It is about local community resources, events, or services in the King County area
          - The location field indicates a King County location

          Consider content NOT relevant if:
          - It is clearly about another county, state, or country
          - It discusses local matters from outside the King County area
          - It is about policies or services that do not apply to Washington state

          When in doubt, err on the side of relevance.

          Title: #{title}#{location_info}

          Content:
          #{truncate_content(content)}

          Answer only "yes" or "no" - is this content relevant to a King County, Washington audience?
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
