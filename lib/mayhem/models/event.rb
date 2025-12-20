# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class Event < FMRepo::Record
      repository_role :events
      scope glob: '_events/**/*.{md,markdown}'
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "_events/#{slug}.md"
      end

      def end_date
        self['end_date']
      end

      def feed_content
        self['feed_content']
      end

      def feed_content_checksum
        self['feed_content_checksum']
      end

      def generated_from_post
        self['generated_from_post']
      end

      def generated_from_post?
        self['generated_from_post'] == true
      end

      def images
        self['images']
      end

      def location
        self['location']
      end

      def locations
        self['locations']
      end

      def locked
        self['locked']
      end

      def locked?
        self['locked'] == true
      end

      def organization_title
        self['organization_title']
      end

      def original_source_html
        self['original_source_html']
      end

      def published
        self['published']
      end

      def published?
        self['published'] != false
      end

      def start_date
        self['start_date']
      end

      def source_url
        self['source_url']
      end

      def summarized
        self['summarized']
      end

      def summarized?
        self['summarized'] == true
      end

      def title
        self['title']
      end

      def topics
        self['topics']
      end
    end
  end
end
