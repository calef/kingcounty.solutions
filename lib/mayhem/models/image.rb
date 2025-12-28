# frozen_string_literal: true

require_relative 'abstract_jekyll_collection'
require_relative 'concerns/sourced'

module Mayhem
  module Models
    class Image < AbstractJekyllCollection
      include Mayhem::Models::Concerns::Sourced

      repository_role :images
      scope glob: '_images/**/*.{md,markdown}'
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

      def image_url
        self['image_url']
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
        checksum_value = checksum.to_s.strip
        return [] if checksum_value.empty?

        model.all.select do |record|
          Array(record.image_checksums).map(&:to_s).map(&:strip).include?(checksum_value)
        end
      end
    end
  end
end
