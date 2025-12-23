# frozen_string_literal: true

module Mayhem
  module Models
    module Concerns
      module Sourced
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
