# frozen_string_literal: true

module Mayhem
  module News
    class RssImporter
      class FeedStats
        LABELS = {
          created: 'created',
          duplicates: 'duplicates',
          not_found: 'not_found',
          stale: 'stale',
          missing_link: 'missing_link',
          missing_title: 'missing_title',
          missing_publish_date: 'missing_date',
          empty_content: 'no_content',
          skipped_unpublished: 'unpublished_locked',
          unchanged: 'unchanged',
          locked: 'locked'
        }.freeze

        def initialize
          @counts = Hash.new(0)
        end

        def increment(key)
          @counts[key] += 1
        end

        def [](key)
          @counts[key]
        end

        def summary_line(source_title, rss_url)
          parts = LABELS.map do |key, label|
            value = @counts[key]
            "#{label}=#{value}" if value&.positive?
          end.compact
          status = parts.empty? ? 'no_changes' : parts.join(', ')
          "Processed '#{source_title}' (#{rss_url}): #{status}"
        end
      end
    end
  end
end
