# frozen_string_literal: true

require_relative '../organization'

module Mayhem
  module Models
    module Concerns
      module Sourced
        # TODO: check my work
        def organization
          Organization.find_by(title: organization_title)
        end

        def organization_title
          self['organization_title']
        end

        def source_url
          self['source_url']
        end
      end
    end
  end
end
