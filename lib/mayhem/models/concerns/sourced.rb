# frozen_string_literal: true

require_relative '../organization'
require_relative 'front_matter_accessors'

module Mayhem
  module Models
    module Concerns
      # Provides source tracking attributes for content models.
      # Includes organization_title and source_url properties.
      module Sourced
        def self.included(base)
          base.include(FrontMatterAccessors) unless base.include?(FrontMatterAccessors)
          base.fm_accessor :organization_title, :source_url
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
