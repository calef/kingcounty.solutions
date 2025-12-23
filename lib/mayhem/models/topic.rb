# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_jekyll_collection'

module Mayhem
  module Models
    class Topic < AbstractJekyllCollection
      repository_role :topics
      scope glob: '_topics/**/*.{md,markdown}'
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "_topics/#{slug}.md"
      end
    end
  end
end
