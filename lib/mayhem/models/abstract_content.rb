# frozen_string_literal: true

require_relative 'abstract_organization_jekyll_collection'

module Mayhem
  module Models
    class AbstractContent < AbstractOrganizationJekyllCollection
      def feed_content
        self['feed_content']
      end

      def feed_content_checksum
        self['feed_content_checksum']
      end

      def image_ids
        self['image_ids'] || []
      end

      def location_titles
        self['location_titles'] || []
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

      def source_url
        self['source_url']
      end

      def summarized
        self['summarized']
      end

      def summarized?
        self['summarized'] == true
      end

      def topic_titles
        self['topic_titles'] || []
      end
    end
  end
end
