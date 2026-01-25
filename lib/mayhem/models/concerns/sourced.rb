# frozen_string_literal: true

require_relative '../organization'

module Mayhem
  module Models
    module Concerns
      # Provides source tracking attributes for content models.
      # Includes organization_title and source_url properties.
      module Sourced
        def self.included(base)
          base.attribute :organization_title, :source_url
        end

        # Returns the Organization record for the organization_title.
        # Returns nil if the organization cannot be found.
        def organization
          Organization.find_by(title: organization_title)
        end
      end
    end
  end
end
