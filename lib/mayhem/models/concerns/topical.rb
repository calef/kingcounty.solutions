# frozen_string_literal: true

module Mayhem
  module Models
    module Concerns
      module Topical
        def topic_titles
          self['topic_titles'] || []
        end
      end
    end
  end
end
