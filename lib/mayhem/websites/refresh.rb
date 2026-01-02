# frozen_string_literal: true

require 'seldon'
require_relative '../models/website'
require_relative '../robots/refresh'
require_relative '../sitemaps/refresh'
require_relative '../sitemap/discovery'

module Mayhem
  module Websites
    class Refresh
      include Seldon::Loggable

      def initialize(http_client: nil, sitemap_finder: nil, robots_refresher: nil, sitemaps_refresher: nil)
        @http = http_client || Seldon::Support::HttpClient.new
        finder = sitemap_finder || Mayhem::SitemapDiscovery::Finder.new(http_client: @http)
        @sitemap_finder = finder
        @robots_refresher = robots_refresher || Mayhem::Robots::Refresh.new(http_client: @http)
        @sitemaps_refresher = sitemaps_refresher || Mayhem::Sitemaps::Refresh.new(http_client: @http)
      end

      def run
        Mayhem::Models::Website.all.each do |website|
          refresh(website)
        end
      end

      def refresh(website)
        refresh_website(website)
      end

      private

      def refresh_website(website)
        robots_url = @robots_refresher.refresh(website)
        return [] unless robots_url

        raw_urls = @sitemap_finder.find(website.homepage_url)
        sitemap_urls = prefer_gz_versions(normalize_url_list(raw_urls))

        update_website_xml_sitemap_urls(website, sitemap_urls)
        @sitemaps_refresher.refresh(website, sitemap_urls) if sitemap_urls.any?
        sitemap_urls
      rescue StandardError => e
        logger.warn "Failed to refresh website #{website.id}: #{e.message}"
        []
      end

      def update_website_xml_sitemap_urls(website, sitemap_urls)
        normalized_existing = normalize_url_list(website.xml_sitemap_urls)
        return if normalized_existing == sitemap_urls

        website['xml_sitemap_urls'] = sitemap_urls
        website.save!
        logger.info "Updated #{website.id} xml_sitemap_urls -> #{sitemap_urls.join(', ')}"
      end

      def normalize_url(value, base_url = nil)
        return nil if value.nil?

        Seldon::Support::UrlNormalizer.normalize(value, base: base_url)
      rescue StandardError
        nil
      end

      def normalize_url_list(urls)
        seen = {}
        Array(urls).filter_map do |url|
          normalized = normalize_url(url)
          next unless normalized
          next if seen[normalized]

          seen[normalized] = true
          normalized
        end
      end

      def prefer_gz_versions(urls)
        gz_bases = urls.each_with_object(Set.new) do |url, bases|
          stripped = strip_gz(url)
          bases.add(stripped) if stripped != url
        end

        seen = Set.new
        urls.each_with_object([]) do |url, collection|
          next if seen.include?(url)

          seen.add(url)
          stripped = strip_gz(url)
          next if gz_bases.include?(stripped) && !url_downcase_end_with_gz?(url)

          collection << url
        end
      end

      def strip_gz(url)
        url.sub(/\.gz(?=$|\?)/i, '')
      end

      def url_downcase_end_with_gz?(url)
        url.downcase.end_with?('.gz')
      end
    end
  end
end
