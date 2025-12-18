# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class Location < FMRepo::Record
      repository_role :locations
      scope glob: '_locations/**/*.{md,markdown}'
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "_locations/#{slug}.md"
      end

      def title
        self['title']
      end

      def location_type
        self['type']
      end

      def parent_location
        self['parent_location']
      end
    end
  end
end
