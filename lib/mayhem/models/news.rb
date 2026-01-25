# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_content'

module Mayhem
  module Models
    class News < AbstractContent
      repository_role :news
      scope glob: '_posts/**/*.md'
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        date = front_matter['date']
        date_prefix = if date.respond_to?(:strftime)
                        date.strftime('%Y-%m-%d')
                      elsif date.is_a?(String)
                        date.split('T').first
                      else
                        Time.now.strftime('%Y-%m-%d')
                      end
        "_posts/#{date_prefix}-#{slug}.md"
      end

      fm_accessor :date, :rss_guid
      fm_accessor :event_ids, default: []
      fm_boolean :events_extracted

      def events
        require_relative 'event'
        event_ids.map do |event_id|
          Event.find(event_id)
        end
      end
    end
  end
end
