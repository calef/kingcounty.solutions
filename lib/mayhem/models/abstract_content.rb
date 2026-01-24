# frozen_string_literal: true

require_relative 'abstract_jekyll_collection'
require_relative 'concerns/located'
require_relative 'concerns/sourced'
require_relative 'concerns/topical'

module Mayhem
  module Models
    class AbstractContent < AbstractJekyllCollection
      include Mayhem::Models::Concerns::Located
      include Mayhem::Models::Concerns::Sourced
      include Mayhem::Models::Concerns::Topical

      def feed_content
        self['feed_content']
      end

      def feed_content=(value)
        self['feed_content'] = value
      end

      def feed_content_checksum
        self['feed_content_checksum']
      end

      def feed_content_checksum=(value)
        self['feed_content_checksum'] = value
      end

      def image_checksums
        self['image_checksums'] || []
      end

      def image_checksums=(value)
        self['image_checksums'] = value
      end

      # Returns Image records for each checksum in image_checksums.
      # Images that cannot be found are excluded from the result.
      def images
        require_relative 'image'

        image_checksums.filter_map do |checksum|
          Image.find_by(checksum:)
        end
      end

      def locked
        self['locked']
      end

      def locked=(value)
        self['locked'] = value
      end

      def locked?
        self['locked'] == true
      end

      def original_source_html
        self['original_source_html']
      end

      def original_source_html=(value)
        self['original_source_html'] = value
      end

      def summarized
        self['summarized']
      end

      def summarized=(value)
        self['summarized'] = value
      end

      def summarized?
        self['summarized'] == true
      end
    end
  end
end
