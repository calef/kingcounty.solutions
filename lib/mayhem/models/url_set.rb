# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_sitemap'

module Mayhem
  module Models
    class UrlSet < AbstractSitemap
      COLLECTION_DIR = '_url_sets'

      repository_role :url_sets
      scope glob: "#{COLLECTION_DIR}/**/*.{md,markdown}"
      naming do |front_matter:, **|
        slug_source = front_matter['url']
        slug = FMRepo.slugify(slug_source)
        "#{COLLECTION_DIR}/#{slug}.md"
      end
    end
  end
end
