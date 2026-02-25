# frozen_string_literal: true

require_relative 'abstract_jekyll_collection'
require_relative 'concerns/relatable'
require_relative 'concerns/sourced'

module Mayhem
  module Models
    class Image < AbstractJekyllCollection
      include Mayhem::Models::Concerns::Relatable
      include Mayhem::Models::Concerns::Sourced

      repository_role :images
      scope glob: '_images/**/*.md'
      naming do |front_matter:, **|
        checksum = front_matter['checksum'] || 'untitled'
        "_images/#{checksum}.md"
      end

      def checksum
        self['checksum']
      end

      def date
        self['date']
      end

      def alt_text
        self['alt_text']
      end

      def image_url
        self['image_url']
      end

      def news
        require_relative 'news'
        find_related_records(Mayhem::Models::News, match_key: :checksum, target_field: :image_checksums)
      end

      def events
        require_relative 'event'
        find_related_records(Mayhem::Models::Event, match_key: :checksum, target_field: :image_checksums)
      end
    end
  end
end
