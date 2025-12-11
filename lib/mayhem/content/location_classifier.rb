# frozen_string_literal: true

require 'ruby/openai'
require_relative '../logging'
require_relative '../front_matter/document'

module Mayhem
  module Content
    class LocationClassifier
      LOCATIONS_DIR = '_locations'
      DEFAULT_MODEL = ENV.fetch('OPENAI_LOCATION_MODEL', ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini'))

      def initialize(
        locations_dir: LOCATIONS_DIR,
        client: nil,
        model: DEFAULT_MODEL,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @locations_dir = locations_dir
        @model = model
        @client = client || ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
        @logger = logger
        @locations_cache = nil
      end

      def classify(content_text, content_title: nil, content_location: nil, content_source: nil)
        locations = load_locations
        return [] if locations.empty?

        location_list = build_location_list(locations)
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
              @logger.warn "OpenAI error during location classification: #{error_message}"
              break
            end

            result = response.dig('choices', 0, 'message', 'content')&.strip
            return parse_location_response(result, locations) unless result.to_s.empty?
          rescue Faraday::TooManyRequestsError
            @logger.warn "Rate limited during location classification, waiting 5 seconds (attempt #{attempts})"
            sleep 5
          rescue StandardError => e
            @logger.error "Error during location classification: #{e.class} - #{e.message}"
            break
          end
        end

        @logger.warn 'Failed to classify locations after retries'
        []
      end

      private

      def load_locations
        return @locations_cache if @locations_cache

        @locations_cache = []
        Dir.glob(File.join(@locations_dir, '*.md')).each do |file_path|
          document = Mayhem::FrontMatter::Document.load(file_path, logger: @logger)
          next unless document

          front_matter = document.front_matter
          title = front_matter['title']
          next unless title

          slug = File.basename(file_path, '.md')
          @locations_cache << {
            slug: slug,
            title: title,
            type: front_matter['type'],
            parent_place: front_matter['parent_place'],
            description: document.body&.strip,
            zip_codes: Array(front_matter['zip_codes'])
          }
        end

        @locations_cache
      end

      def build_location_list(locations)
        locations.map do |loc|
          parts = [loc[:title]]
          parts << "(#{loc[:type]})" if loc[:type]
          parts << "in #{loc[:parent_place]}" if loc[:parent_place]
          parts.join(' ')
        end.join("\n")
      end

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

      def parse_location_response(response, locations)
        # Try to extract JSON array from response
        json_match = response.match(/\[.*\]/m)
        return [] unless json_match

        begin
          titles = JSON.parse(json_match[0])
          return [] unless titles.is_a?(Array)

          # Validate that returned titles exist in our locations
          valid_titles = locations.map { |loc| loc[:title] }
          titles.select { |title| valid_titles.include?(title) }.uniq
        rescue JSON::ParserError => e
          @logger.warn "Failed to parse location response as JSON: #{e.message}"
          []
        end
      end
    end
  end
end
