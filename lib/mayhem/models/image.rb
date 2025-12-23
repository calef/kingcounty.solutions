# frozen_string_literal: true

require_relative 'abstract_organization_jekyll_collection'

module Mayhem
  module Models
    class Image < AbstractOrganizationJekyllCollection
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

      def source_url
        self['source_url']
      end
    end
  end
end
