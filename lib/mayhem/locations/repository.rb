# frozen_string_literal: true

require_relative '../logging'
require_relative '../front_matter/document'

module Mayhem
  module Locations
    class Repository
      LOCATIONS_DIR = '_locations'

      def initialize(
        locations_dir: LOCATIONS_DIR,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @locations_dir = locations_dir
        @logger = logger
        @locations_cache = nil
      end

      def all
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
            parent_location: front_matter['parent_location'],
            description: document.body&.strip
          }
        end

        @locations_cache
      end

      def build_location_list(locations)
        locations.map do |loc|
          parts = [loc[:title]]
          parts << "(#{loc[:type]})" if loc[:type]
          parts << "in #{loc[:parent_location]}" if loc[:parent_location]
          parts.join(' ')
        end.join("\n")
      end

      def filter_to_highest_level(titles, locations)
        return titles if titles.empty?

        title_to_location = locations.each_with_object({}) do |loc, hash|
          hash[loc[:title]] = loc
        end

        titles.reject do |title|
          location = title_to_location[title]
          next false unless location

          has_ancestor_in_list = false
          current_parent = location[:parent_location]

          while current_parent
            if titles.include?(current_parent)
              has_ancestor_in_list = true
              break
            end

            parent_location = title_to_location[current_parent]
            current_parent = parent_location ? parent_location[:parent_location] : nil
          end

          has_ancestor_in_list
        end
      end
    end
  end
end
