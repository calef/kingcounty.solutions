# frozen_string_literal: true

require 'fmrepo'
require 'uri'
require_relative 'abstract_sitemap'

module Mayhem
  module Models
    class RobotsTxt < AbstractSitemap
      COLLECTION_DIR = '_robots_txts'

      repository_role :robots_txts
      scope glob: "#{COLLECTION_DIR}/**/*.{txt}"
      naming do |front_matter:, **|
        url = front_matter['url']
        slug_source = extract_domain(url) || url
        slug = FMRepo.slugify(slug_source)
        "#{COLLECTION_DIR}/#{slug}-robots.txt"
      end

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
    end
  end
end
