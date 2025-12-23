# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_jekyll_collection'
require_relative 'concerns/topical'

module Mayhem
  module Models
    class Organization < AbstractJekyllCollection
      include Mayhem::Models::Concerns::Topical

      repository_role :organizations
      scope glob: '_organizations/**/*.{md,markdown}'
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "_organizations/#{slug}.md"
      end

      def acronym
        self['acronym']
      end

      def address
        self['address']
      end

      def email
        self['email']
      end

      def events_ical_url
        self['events_ical_url']
      end

      def news_rss_url
        self['news_rss_url']
      end

      def parent_organization_title
        self['parent_organization_title']
      end

      def parent_organization
        return nil if parent_organization_title.nil? || parent_organization_title.empty?

        self.class.find_by(title: parent_organization_title)
      end

      def parent_organization?
        !parent_organization.nil?
      end

      def phone
        self['phone']
      end

      def type
        self['type']
      end

      def website_url
        self['website_url']
      end

      def website_xml_sitemap_urls
        self['website_xml_sitemap_urls'] || []
      end
    end
  end
end
