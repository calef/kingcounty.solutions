# frozen_string_literal: true

require_relative '../logging'
require_relative '../front_matter/document'

module Mayhem
  module Content
    class LocationRepository
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

      def filter_to_highest_level(titles, locations)
        return titles if titles.empty?

        # Build a map of title to location for easy lookup
        title_to_location = locations.each_with_object({}) do |loc, hash|
          hash[loc[:title]] = loc
        end

        # For each location, check if any of its ancestors are also in the list
        # If so, remove the child location
        titles.reject do |title|
          location = title_to_location[title]
          next false unless location

          # Walk up the parent chain to see if any ancestor is in the titles list
          has_ancestor_in_list = false
          current_parent = location[:parent_place]

          while current_parent
            if titles.include?(current_parent)
              has_ancestor_in_list = true
              break
            end

            # Move to the next level up
            parent_location = title_to_location[current_parent]
            current_parent = parent_location ? parent_location[:parent_place] : nil
          end

          has_ancestor_in_list
        end
      end
    end
  end
end
