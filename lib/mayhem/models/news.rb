# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_content'

module Mayhem
  module Models
    class News < AbstractContent
      repository_role :news
      scope glob: '_posts/**/*.{md,markdown}'
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

      def date
        self['date']
      end

      # TODO: add events def that looks up the events by their id
      def event_ids
        self['event_ids'] || []
      end

      def events_extracted
        self['events_extracted']
      end

      def events_extracted?
        self['events_extracted'] == true
      end

      def rss_guid
        self['rss_guid']
      end
    end
  end
end
