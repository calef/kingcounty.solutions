# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_jekyll_collection'

module Mayhem
  module Models
    class Location < AbstractJekyllCollection
      repository_role :locations
      scope glob: '_locations/**/*.{md,markdown}'
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

      def parent_location
        self.class.find_by(title: parent_location_title)
      end

      def parent_location?
        !parent_location.nil?
      end

      def news
        require_relative 'news'
        related_records(Mayhem::Models::News)
      end

      def events
        require_relative 'event'
        related_records(Mayhem::Models::Event)
      end

      private

      def related_records(model)
        title_value = title.to_s.strip
        return [] if title_value.empty?

        model.all.select do |record|
          Array(record.location_titles).map(&:to_s).map(&:strip).include?(title_value)
        end
      end
    end
  end
end
