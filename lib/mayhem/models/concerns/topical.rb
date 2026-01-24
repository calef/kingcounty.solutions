# frozen_string_literal: true

require_relative '../topic'

module Mayhem
  module Models
    module Concerns
      module Topical
        # Returns Topic records for each title in topic_titles.
        # Topics that cannot be found are excluded from the result.
        def topics
          topic_titles.filter_map do |topic_title|
            Topic.find_by(title: topic_title)
          end
        end

        def topic_titles
          self['topic_titles'] || []
        end

        def topic_titles=(value)
          self['topic_titles'] = value
        end
      end
    end
  end
end
