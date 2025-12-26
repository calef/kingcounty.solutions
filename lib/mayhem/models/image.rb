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

      # TODO: add news and events methods to look up news and events that reference this image
    end
  end
end
