# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_jekyll_collection'

module Mayhem
  module Models
    class Website < AbstractJekyllCollection
      COLLECTION_DIR = '_websites'

      repository_role :websites
      scope glob: "#{COLLECTION_DIR}/**/*.{md,markdown}"
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'url'
        slug = FMRepo.slugify(slug_source)
        "#{COLLECTION_DIR}/#{slug}.md"
      end

      def events_ical_url
        self['events_ical_url']
      end

      def organization
        require_relative 'organization'
        Organization.find_by(website_url: homepage_url)
      end

      def homepage_url
        self['homepage_url']
      end

      def robots_txt_url
        self['robots_txt_url']
      end

      def xml_sitemap_urls
        self['xml_sitemap_urls'] || []
      end
    end
  end
end
