# frozen_string_literal: true

require 'seldon'
require_relative '../models/location'

module Mayhem
  module Locations
    # Repository for accessing and querying location data.
    #
    # Locations form a hierarchy (e.g., King County -> Seattle -> Capitol Hill).
    # This repository provides methods to list locations and filter them by
    # their position in the hierarchy.
    class Repository
      include Seldon::Loggable

      def initialize(
        location_repo: nil,
        location_model: Mayhem::Models::Location
      )
        @location_repo = location_repo
        @location_model = location_model
        @locations_cache = nil
      end

      # Returns all locations as an array of hashes.
      # Results are cached after first call.
      #
      # @return [Array<Hash>] Location hashes with :id, :title, :type,
      #   :parent_location_title, and :description keys
      def all
        return @locations_cache if @locations_cache

        relation = @location_model.relation(repo: @location_repo)
        @locations_cache = relation.to_a.each_with_object([]) do |location, locations|
          next unless location.title

          locations << build_location_hash(location)
        end
      end

      # Builds a human-readable list of locations for use in prompts.
      # Each location is formatted as: "Title (type) in Parent"
      #
      # @param locations [Array<Hash>] Location hashes from #all
      # @return [String] Newline-separated list of formatted location strings
      def build_location_list(locations)
        locations.map do |loc|
          parts = [loc[:title]]
          parts << "(#{loc[:type]})" if loc[:type]
          parts << "in #{loc[:parent_location_title]}" if loc[:parent_location_title]
          parts.join(' ')
        end.join("\n")
      end

      # Filters location titles to retain only the highest-level ancestors,
      # removing any locations whose parent (or grandparent, etc.) is also in the list.
      #
      # This prevents redundant location assignments. For example, if content is
      # relevant to both "Seattle" and "King County", and Seattle is a child of
      # King County, we only keep "King County" since it implicitly includes Seattle.
      #
      # Algorithm:
      #   1. Build a lookup table mapping titles to location data
      #   2. For each title in the input list:
      #      a. Walk up the parent chain (parent -> grandparent -> ...)
      #      b. If any ancestor is also in the input list, mark this title for removal
      #   3. Return titles that have no ancestors in the list
      #
      # Example:
      #   Given locations: King County -> Seattle -> Capitol Hill
      #   Input: ["Capitol Hill", "Seattle", "King County", "Bellevue"]
      #   Output: ["King County", "Bellevue"]
      #   (Capitol Hill removed because Seattle is in list;
      #    Seattle removed because King County is in list;
      #    Bellevue kept because its parent King County doesn't make it redundant)
      #
      # Time complexity: O(n * d) where n = number of titles, d = max depth of hierarchy
      #
      # @param titles [Array<String>] Location titles to filter
      # @param locations [Array<Hash>] Location data with :title and :parent_location_title keys
      # @return [Array<String>] Filtered titles containing only highest-level locations
      def filter_to_highest_level(titles, locations)
        return titles if titles.empty?

        title_to_location = locations.to_h do |loc|
          [loc[:title], loc]
        end

        titles.reject do |title|
          location = title_to_location[title]
          next false unless location

          has_ancestor_in_list = false
          current_parent = location[:parent_location_title]

          # Walk up the parent chain looking for ancestors in the input list
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
