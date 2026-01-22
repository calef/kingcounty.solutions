# frozen_string_literal: true

require_relative '../location'

module Mayhem
  module Models
    module Concerns
      module Located
        def location_titles
          self['location_titles'] || []
        end

        def location_titles=(value)
          self['location_titles'] = value
        end

        def locations
          location_titles.map do |location_title|
            Location.find_by(title: location_title)
          end
        end
      end
    end
  end
end
