# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_jekyll_collection'
require_relative 'concerns/relatable'

module Mayhem
  module Models
    class Location < AbstractJekyllCollection
      include Mayhem::Models::Concerns::Relatable

      repository_role :locations
      scope glob: '_locations/**/*.md'
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "_locations/#{slug}.md"
      end

      def location_type
        self['type']
      end

      def parent_location_title
        self['parent_location_title']
      end

      # Returns the parent Location record.
      # Returns nil if the parent cannot be found.
      def parent_location
        self.class.find_by(title: parent_location_title)
      end

      def parent_location?
        !parent_location.nil?
      end

      def news
        require_relative 'news'
        find_related_records(Mayhem::Models::News, match_key: :title, target_field: :location_titles)
      end

      def events
        require_relative 'event'
        find_related_records(Mayhem::Models::Event, match_key: :title, target_field: :location_titles)
      end
    end
  end
end
