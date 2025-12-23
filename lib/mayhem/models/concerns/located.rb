# frozen_string_literal: true

module Mayhem
  module Models
    module Concerns
      module Located
        def location_titles
          self['location_titles'] || []
        end
      end
    end
  end
end
