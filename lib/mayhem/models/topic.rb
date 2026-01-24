# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_jekyll_collection'
require_relative 'concerns/relatable'

module Mayhem
  module Models
    class Topic < AbstractJekyllCollection
      include Mayhem::Models::Concerns::Relatable

      repository_role :topics
      scope glob: '_topics/**/*.md'
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "_topics/#{slug}.md"
      end

      def organizations
        require_relative 'organization'
        find_related_records(Mayhem::Models::Organization, match_key: :title, target_field: :topic_titles)
      end

      def news
        require_relative 'news'
        find_related_records(Mayhem::Models::News, match_key: :title, target_field: :topic_titles)
      end

      def events
        require_relative 'event'
        find_related_records(Mayhem::Models::Event, match_key: :title, target_field: :topic_titles)
      end
    end
  end
end
