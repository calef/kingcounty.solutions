# frozen_string_literal: true

require 'fmrepo'
require_relative 'abstract_jekyll_collection'
require_relative 'concerns/relatable'
require_relative 'concerns/topical'

module Mayhem
  module Models
    class Organization < AbstractJekyllCollection
      include Mayhem::Models::Concerns::Relatable
      include Mayhem::Models::Concerns::Topical

      COLLECTION_DIR = '_organizations'

      repository_role :organizations
      scope glob: "#{COLLECTION_DIR}/**/*.md"
      naming do |front_matter:, **|
        slug_source = front_matter['slug'] || front_matter['title'] || 'untitled'
        slug = FMRepo.slugify(slug_source)
        "#{COLLECTION_DIR}/#{slug}.md"
      end

      attribute :acronym, :address, :email, :events_ical_url
      attribute :news_rss_url, :parent_organization_title, :phone
      attribute :type, :website_url
      attribute :website_xml_sitemap_urls, default: []

      def news
        require_relative 'news'
        find_related_records(Mayhem::Models::News, match_key: :title, target_field: :organization_title, array_field: false)
      end

      def events
        require_relative 'event'
        find_related_records(Mayhem::Models::Event, match_key: :title, target_field: :organization_title, array_field: false)
      end

      def images
        require_relative 'image'
        find_related_records(Mayhem::Models::Image, match_key: :title, target_field: :organization_title, array_field: false)
      end

      # Returns the parent Organization record.
      # Returns nil if no parent is configured or the parent cannot be found.
      def parent_organization
        return nil if parent_organization_title.nil? || parent_organization_title.empty?

        self.class.find_by(title: parent_organization_title)
      end

      def parent_organization?
        !parent_organization.nil?
      end
    end
  end
end
