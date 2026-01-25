# frozen_string_literal: true

require_relative '../location'

module Mayhem
  module Models
    module Concerns
      # Provides location association attributes for content models.
      # Includes location_titles property and locations accessor.
      module Located
        def self.included(base)
          base.attribute :location_titles, default: []
        end

        # Returns Location records for each title in location_titles.
        # Locations that cannot be found are excluded from the result.
        def locations
          location_titles.filter_map do |location_title|
            Location.find_by(title: location_title)
          end
        end
      end
    end
  end
end
