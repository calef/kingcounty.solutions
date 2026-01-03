# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_jekyll_collection'

module Mayhem
  module Models
    class Topic < AbstractJekyllCollection
      repository_role :topics
      scope glob: '_topics/**/*.md'
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "_topics/#{slug}.md"
      end

      def organizations
        require_relative 'organization'
        related_records(Mayhem::Models::Organization)
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
          Array(record.topic_titles).map(&:to_s).map(&:strip).include?(title_value)
        end
      end
    end
  end
end
