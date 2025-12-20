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

      def title
        self['title']
      end

      def start_date
        self['start_date']
      end

      def end_date
        self['end_date']
      end

      def location
        self['location']
      end

      def source
        self['source']
      end

      def source_url
        self['source_url']
      end
    end
  end
end
