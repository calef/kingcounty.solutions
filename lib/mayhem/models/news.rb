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

      def title
        self['title']
      end

      def date
        self['date']
      end

      def source
        self['source']
      end

      def source_url
        self['source_url']
      end

      def topics
        self['topics'] || []
      end

      def locations
        self['locations'] || []
      end

      def images
        self['images'] || []
      end

      def events
        self['events'] || []
      end

      def published?
        self['published'] != false
      end

      def summarized?
        self['summarized'] == true
      end
    end
  end
end
