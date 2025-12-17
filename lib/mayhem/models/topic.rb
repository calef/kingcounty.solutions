# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class Topic < FMRepo::Record
      DEFAULT_REPOSITORY_ROOT = File.expand_path('../../..', __dir__)

      repository DEFAULT_REPOSITORY_ROOT

      scope glob: '_topics/**/*.{md,markdown}'

      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "_topics/#{slug}.md"
      end

      def title
        self['title']
      end
    end
  end
end
