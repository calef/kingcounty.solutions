# frozen_string_literal: true

require_relative '../logging'
require_relative '../models/location'

module Mayhem
  module Locations
    class Repository
      include Mayhem::Loggable

      def initialize(
        location_repo: nil,
        location_model: Mayhem::Models::Location
      )
        @location_repo = location_repo
        @location_model = location_model
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
          parts << "in #{loc[:parent_location_title]}" if loc[:parent_location_title]
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
          current_parent = location[:parent_location_title]

          while current_parent
            if titles.include?(current_parent)
              has_ancestor_in_list = true
              break
            end

            parent_location = title_to_location[current_parent]
            current_parent = parent_location ? parent_location[:parent_location_title] : nil
          end

          has_ancestor_in_list
        end
      end

      private

      def build_location_hash(location)
        {
          id: location.id,
          title: location.title,
          type: location.location_type,
          parent_location_title: location.parent_location_title,
          description: location.body&.strip
        }
      end
    end
  end
end
