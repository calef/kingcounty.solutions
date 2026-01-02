# frozen_string_literal: true

require 'nokogiri'
require 'uri'
require 'seldon'
require_relative '../models/website'
require_relative '../feed/discovery'
require_relative '../sitemap/discovery'

module Mayhem
  module Websites
    class Generator
      include Seldon::Loggable

      WEBSITE_SCRAPER_TIMEOUT = Integer(ENV.fetch('WEBSITE_SCRAPER_TIMEOUT', 10))

      def initialize(http_client: nil, feed_finder: nil, sitemap_finder: nil)
        @http = http_client || Seldon::Support::HttpClient.new(timeout: WEBSITE_SCRAPER_TIMEOUT)
        @feed_finder = feed_finder || Mayhem::FeedDiscovery::FeedFinder.new(@http)
        @sitemap_finder = sitemap_finder || Mayhem::SitemapDiscovery::Finder.new(http_client: @http)
      end

      def run(raw_url)
        abort "Usage: #{File.basename($PROGRAM_NAME)} URL" unless raw_url

        website_url = canonical_url(raw_url)
        existing = Mayhem::Models::Website.find_by(homepage_url: website_url)
        if existing
          logger.info "Website with homepage #{website_url} already exists; skipping."
          return
        end

        title = homepage_title(website_url) || fallback_title(website_url)
        feed_result = discover_feed_urls(website_url)
        sitemap_urls = discover_sitemap_urls(website_url)

        front_matter = {
          'title' => title,
          'homepage_url' => website_url
        }

        if feed_result && (ical_url = Seldon::Support::ValueNormalizer.normalize_value(feed_result.ical_url))
          front_matter['events_ical_url'] = ical_url
        end
        front_matter['xml_sitemap_urls'] = sitemap_urls.uniq if sitemap_urls&.any?

        website = Mayhem::Models::Website.create!(front_matter, body: '')
        logger.info "Created #{website.id}"
      end

      private

      def canonical_url(url)
        Seldon::Support::UrlNormalizer.normalize(url)
      end

      def homepage_title(url)
        page = @http.fetch(url, accept: Mayhem::FeedDiscovery::ACCEPT_HTML)
        doc = Nokogiri::HTML(page[:body])
        title = doc.at('title')&.text.to_s.gsub(/\s+/, ' ').strip
        title.empty? ? nil : title
      rescue StandardError => e
        logger.warn "Homepage title fetch failed for #{url}: #{e.message}"
        nil
      end

      def fallback_title(url)
        URI.parse(url).host
      rescue URI::InvalidURIError
        url.to_s
      end

      def discover_feed_urls(website_url)
        return nil unless website_url

        @feed_finder&.find(website_url)
      rescue StandardError => e
        logger.warn "Feed discovery failed for #{website_url}: #{e.message}"
        nil
      end

      def discover_sitemap_urls(website_url)
        return nil unless website_url

        @sitemap_finder&.find(website_url) || []
      rescue StandardError => e
        logger.warn "Sitemap discovery failed for #{website_url}: #{e.message}"
        []
      end

      def base_url_for(website_url)
        normalized = Seldon::Support::UrlNormalizer.normalize(website_url)
        return nil unless normalized

        uri = URI.parse(normalized)
        return nil unless uri.scheme && uri.host

        base = "#{uri.scheme}://#{uri.host}"
        base += ":#{uri.port}" if uri.port && uri.port != uri.default_port
        base
      rescue URI::Error
        nil
      end
    end
  end
end
