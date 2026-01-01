# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class AbstractSitemap < FMRepo::Record
      def self.extract_domain(url)
        return unless url

        uri = URI.parse(url.to_s)
        return unless uri.host

        host = uri.host
        port_suffix = uri.port && uri.port != uri.default_port ? "-#{uri.port}" : ''
        "#{host}#{port_suffix}"
      rescue URI::InvalidURIError
        nil
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
