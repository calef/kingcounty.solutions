# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class AbstractSitemap < FMRepo::Record
      def last_modified
        self['last_modified']
      end

      def last_modified
        self['last_modified']
      end

      def url
        self['url']
      end

      def website
        require_relative 'website'
        Website.find(website_id)
      end

      def website_id
        self['website_id']
      end
    end
  end
end
