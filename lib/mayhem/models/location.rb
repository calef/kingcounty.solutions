# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    # Location model represents geographic locations, such as cities,
    # neighborhoods, and regions. Each location is stored as a markdown file in the
    # _locations directory with front matter containing location metadata.
    #
    # This model integrates with FMRepo (Front Matter Repository), which provides
    # ActiveRecord-style querying for front matter documents. The Location class
    # inherits from FMRepo::Record to enable reading, writing, and querying location
    # data stored in markdown files with YAML front matter.
    #
    # Location files contain:
    # - title: The location name (e.g., "Seattle", "Redmond")
    # - type: The location type (e.g., "City", "Neighborhood", "Region")
    # - parent_location: The parent location name for hierarchical relationships
    # - body: Markdown content describing the location
    class Location < FMRepo::Record
      DEFAULT_REPOSITORY_ROOT = File.expand_path('../../..', __dir__)

      repository DEFAULT_REPOSITORY_ROOT

      scope glob: '_locations/**/*.{md,markdown}'

      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "_locations/#{slug}.md"
      end

      # Returns the location's title from the front matter.
      #
      # @return [String, nil] the location's display name (e.g., "Seattle", "Redmond")
      def title
        self['title']
      end

      # Returns the location's type from the front matter.
      #
      # @return [String, nil] the type of location (e.g., "City", "Neighborhood", "Region")
      def location_type
        self['type']
      end

      # Returns the parent location's title from the front matter.
      # Used to establish hierarchical relationships between locations.
      #
      # @return [String, nil] the parent location's title (e.g., "Eastside" for "Redmond")
      def parent_location
        self['parent_location']
      end
    end
  end
end
