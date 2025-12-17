# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    # Location model represents a geographic location in King County.
    #
    # This model integrates with FMRepo to manage location documents as Ruby objects,
    # providing a structured way to access location data stored in markdown files.
    # Locations are hierarchical, with each location optionally having a parent location.
    class Location < FMRepo::Record
      DEFAULT_REPOSITORY_ROOT = File.expand_path('../../..', __dir__)

      repository DEFAULT_REPOSITORY_ROOT

      scope glob: '_locations/**/*.{md,markdown}'

      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "_locations/#{slug}.md"
      end

      # Returns the location's title.
      #
      # @return [String, nil] the location title from the front matter
      def title
        self['title']
      end

      # Returns the location's type (e.g., 'county', 'city', 'region').
      #
      # @return [String, nil] the location type from the front matter
      def location_type
        self['type']
      end

      # Returns the slug of the parent location in the hierarchy.
      #
      # @return [String, nil] the parent location slug from the front matter
      def parent_location
        self['parent_location']
      end
    end
  end
end
