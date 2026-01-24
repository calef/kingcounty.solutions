# frozen_string_literal: true

require 'json'
require 'ruby/openai'
require 'seldon'
require_relative 'repository'

module Mayhem
  module Locations
    class Classifier
      include Seldon::Loggable

      DEFAULT_MODEL = ENV.fetch('OPENAI_LOCATION_MODEL', ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini'))

      def initialize(
        location_repository: nil,
        client: nil,
        model: DEFAULT_MODEL
      )
        @location_repository = location_repository || Repository.new
        @model = model
        @client = client || ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
      end

      def classify(content_text, content_title: nil, content_location: nil, content_source: nil)
        locations = @location_repository.all
        return [] if locations.empty?

        location_list = @location_repository.build_location_list(locations)
        prompt = build_prompt(content_text, content_title, content_location, content_source, location_list)

        attempts = 0
        while attempts < 3
          attempts += 1
          begin
            response = @client.chat(
              parameters: {
                model: @model,
                messages: [
                  { role: 'system', content: 'You are a helpful assistant who classifies content by geographic relevance.' },
                  { role: 'user', content: prompt }
                ],
                temperature: 0.3
              }
            )

            if (error_message = response.dig('error', 'message'))
              logger.warn "OpenAI error during location classification: #{error_message}"
              break
            end

            result = response.dig('choices', 0, 'message', 'content')&.strip
            return parse_location_response(result, locations) unless result.to_s.empty?
          rescue Faraday::TooManyRequestsError
            logger.warn "Rate limited during location classification, waiting 5 seconds (attempt #{attempts})"
            sleep 5
          rescue StandardError => e
            logger.error "Error during location classification: #{e.class} - #{e.message}"
            break
          end
        end

        logger.warn 'Failed to classify locations after retries'
        []
      end

      private

      def build_prompt(content_text, content_title, content_location, content_source, location_list)
        prompt_parts = []
        prompt_parts << "Content Title: #{content_title}" if content_title
        prompt_parts << "Content Source: #{content_source}" if content_source
        prompt_parts << "Content Location: #{content_location}" if content_location
        prompt_parts << "\nContent:\n#{content_text}"

        <<~PROMPT
          Determine which of the following King County locations would find this content relevant and interesting.
          A location is relevant if the content is more likely than not to be something that a resident of that location would find interesting or useful.

          Consider:
          - Geographic specificity: Is the content specifically about or taking place in a location?
          - Regional scope: Does the content apply to the broader region (like "King County" or "Seattle" for county-wide content)?
          - Topic relevance: Would residents of each location care about this topic?

          Available locations:
          #{location_list}

          #{prompt_parts.join("\n")}

          Respond with a JSON array of location titles (e.g., ["Seattle", "King County"]) that are relevant.
          If no locations are relevant, respond with an empty array: []

          Only include the JSON array in your response, nothing else.
        PROMPT
      end

      # Parses the OpenAI response containing a JSON array of location titles.
      # Validates titles against known locations and filters to highest level.
      #
      # @param response [String] Raw response from OpenAI (should contain JSON array)
      # @param locations [Array<Hash>] Known locations with :title keys
      # @return [Array<String>] Valid location titles, filtered to highest level
      def parse_location_response(response, locations)
        json_match = response.match(/\[.*\]/m)
        return [] unless json_match

        begin
          titles = JSON.parse(json_match[0])
          return [] unless titles.is_a?(Array)

          valid_titles = locations.map { |loc| loc[:title] }
          matched_titles = titles.select { |title| valid_titles.include?(title) }.uniq

          @location_repository.filter_to_highest_level(matched_titles, locations)
        rescue JSON::ParserError => e
          logger.warn "Failed to parse location response as JSON: #{e.message}"
          []
        end
      end
    end
  end
end
