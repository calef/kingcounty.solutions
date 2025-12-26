# frozen_string_literal: true

require_relative 'abstract_jekyll_collection'
require_relative 'concerns/located'
require_relative 'concerns/sourced'
require_relative 'concerns/topical'
require_relative 'image'

module Mayhem
  module Models
    class AbstractContent < AbstractJekyllCollection
      include Mayhem::Models::Concerns::Located
      include Mayhem::Models::Concerns::Sourced
      include Mayhem::Models::Concerns::Topical

      def feed_content
        self['feed_content']
      end

      def feed_content_checksum
        self['feed_content_checksum']
      end

      def image_checksums
        self['image_checksums'] || []
      end

      def images
        image_checksums.map do |checksum|
          Image.find_by(checksum:)
        end
      end

      def locked
        self['locked']
      end

      def locked?
        self['locked'] == true
      end

      def original_source_html
        self['original_source_html']
      end

      def summarized
        self['summarized']
      end

      def summarized?
        self['summarized'] == true
      end
    end
  end
end
