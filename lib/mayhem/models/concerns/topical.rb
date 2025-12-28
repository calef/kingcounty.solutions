# frozen_string_literal: true

require_relative '../topic'

module Mayhem
  module Models
    module Concerns
      module Topical
        def topics
          topic_titles.map do |topic_title|
            Topic.find_by(title: topic_title)
          end
        end

        def topic_titles
          self['topic_titles'] || []
        end
      end
    end
  end
end
