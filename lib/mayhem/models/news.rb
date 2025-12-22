# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class News < FMRepo::Record
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

      def events
        self['events'] || []
      end

      def events_extracted
        self['events_extracted']
      end

      def events_extracted?
        self['events_extracted'] == true
      end

      def feed_content
        self['feed_content']
      end

      def feed_content_checksum
        self['feed_content_checksum']
      end

      def image_ids
        self['image_ids'] || []
      end

      def locations
        self['locations'] || []
      end

      def locked
        self['locked']
      end

      def locked?
        self['locked'] == true
      end

      def original_source_html
        self['original_source_html']
      end

      def published
        self['published']
      end

      def published?
        # Posts are published by default (nil means published)
        # Only unpublished when explicitly set to false
        self['published'] != false
      end

      def source
        self['source']
      end

      def source_url
        self['source_url']
      end

      def rss_guid
        self['rss_guid']
      end

      def summarized
        self['summarized']
      end

      def summarized?
        # Posts must always have summarized set to true
        self['summarized'] == true
      end

      def title
        self['title']
      end

      def topics
        self['topics'] || []
      end
    end
  end
end
