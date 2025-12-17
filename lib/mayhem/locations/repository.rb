# frozen_string_literal: true

require_relative '../logging'
require_relative '../models/location'

module Mayhem
  module Locations
    class Repository
      def initialize(
        location_repo: nil,
        location_model: Mayhem::Models::Location,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @location_repo = location_repo
        @location_model = location_model
        @location_model.repository(location_repo) if location_repo
        @logger = logger
        @locations_cache = nil
      end

      def all
        return @locations_cache if @locations_cache

        relation = @location_model.relation(repo: @location_repo)
        @locations_cache = relation.to_a.each_with_object([]) do |location, locations|
          next unless location.title

          locations << build_location_hash(location)
        end
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

      private

      def build_location_hash(location)
        rel_path = location.rel_path
        slug = if rel_path
                 rel_path.basename(rel_path.extname).to_s
               else
                 FMRepo.slugify(location.title || '')
               end

        {
          slug: slug,
          title: location.title,
          type: location.location_type,
          parent_location: location.parent_location,
          description: location.body&.strip
        }
      end
    end
  end
end
