# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class Organization < FMRepo::Record
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
        self['parent_organization']
      end

      def parent_organization
        self.class.find_by(title: parent_organization_title)
      end

      def parent_organization?
        !parent_organization.nil?
      end

      def phone
        self['phone']
      end

      def title
        self['title']
      end

      def topics
        self['topics']
      end

      def type
        self['type']
      end

      def website
        self['website']
      end
    end
  end
end
