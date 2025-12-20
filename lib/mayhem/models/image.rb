# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class Image < FMRepo::Record
      repository_role :images
      scope glob: '_images/**/*.{md,markdown}'
      naming do |front_matter:, **|
        checksum = front_matter['checksum'] || 'untitled'
        "_images/#{checksum}.md"
      end

      def checksum
        self['checksum']
      end

      def image_url
        self['image_url']
      end

      def organization_title
        self['organization_title']
      end

      def source_url
        self['source_url']
      end

      def title
        self['title']
      end

      def date
        self['date']
      end
    end
  end
end
