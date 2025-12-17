# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class Image < FMRepo::Record
      DEFAULT_REPOSITORY_ROOT = File.expand_path('../../..', __dir__)

      repository DEFAULT_REPOSITORY_ROOT

      scope glob: '_images/**/*.{md,markdown}'

      naming do |front_matter:, **|
        checksum = front_matter['checksum'] || FMRepo.slugify(front_matter['title'] || 'image')
        "_images/#{checksum}.md"
      end

      def checksum
        self['checksum']
      end

      def title
        self['title']
      end

      def organization_title
        self['organization_title']
      end

      def source_url
        self['source_url']
      end

      def image_url
        self['image_url']
      end

      def date
        self['date']
      end
    end
  end
end
