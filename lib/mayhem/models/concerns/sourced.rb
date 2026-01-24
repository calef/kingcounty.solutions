# frozen_string_literal: true

require_relative '../organization'

module Mayhem
  module Models
    module Concerns
      # Provides source tracking attributes for content models.
      # Includes organization_title and source_url properties.
      module Sourced
        # Returns the Organization record for the organization_title.
        # Returns nil if the organization cannot be found.
        def organization
          Organization.find_by(title: organization_title)
        end

        def organization_title
          self['organization_title']
        end

        def organization_title=(value)
          self['organization_title'] = value
        end

        def source_url
          self['source_url']
        end

        def source_url=(value)
          self['source_url'] = value
        end
      end
    end
  end
end
