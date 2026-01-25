# frozen_string_literal: true

require_relative '../topic'
require_relative 'front_matter_accessors'

module Mayhem
  module Models
    module Concerns
      # Provides topic association attributes for content models.
      # Includes topic_titles property and topics accessor.
      module Topical
        def self.included(base)
          base.include(FrontMatterAccessors) unless base.include?(FrontMatterAccessors)
          base.fm_accessor :topic_titles, default: []
        end

        # Returns Topic records for each title in topic_titles.
        # Topics that cannot be found are excluded from the result.
        def topics
          topic_titles.filter_map do |topic_title|
            Topic.find_by(title: topic_title)
          end
        end
      end
    end
  end
end
