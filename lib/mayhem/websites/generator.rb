# frozen_string_literal: true

require 'nokogiri'
require 'uri'
require_relative '../logging'
require_relative '../models/website'
require_relative '../feed/discovery'
require_relative '../sitemap/discovery'
require_relative '../support/http_client'
require_relative '../support/url_normalizer'
require_relative '../support/url_utils'

module Mayhem
  module Websites
    class Generator
      include Mayhem::Loggable

      WEBSITE_SCRAPER_TIMEOUT = Integer(ENV.fetch('WEBSITE_SCRAPER_TIMEOUT', ENV.fetch('ORG_SCRAPER_TIMEOUT', 10)))

      def initialize(http_client: nil, feed_finder: nil, sitemap_finder: nil)
        @http = http_client || Mayhem::Support::HttpClient.new(timeout: WEBSITE_SCRAPER_TIMEOUT)
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

        if feed_result && (ical_url = normalize_value(feed_result.ical_url))
          front_matter['events_ical_url'] = ical_url
        end
        if (robots_url = robots_txt_url(website_url))
          front_matter['robots_txt_url'] = robots_url
        end
        front_matter['xml_sitemap_urls'] = sitemap_urls.uniq if sitemap_urls&.any?

        website = Mayhem::Models::Website.create!(front_matter, body: '')
        logger.info "Created #{website.id}"
      end

      private

      def canonical_url(url)
        uri = URI(url)
        uri = URI.parse("https://#{url}") if uri.host.nil?
        uri.scheme ||= 'https'
        uri.fragment = nil
        uri.to_s
      rescue URI::InvalidURIError
        url
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

      def normalize_value(value)
        return nil if value.nil?

        if value.is_a?(String)
          trimmed = value.strip
          return nil if trimmed.empty?

          trimmed
        elsif value.respond_to?(:empty?) && value.empty?
          nil
        else
          value
        end
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

      def robots_txt_url(website_url)
        base_url = base_url_for(website_url)
        return nil unless base_url

        Mayhem::Support::UrlUtils.absolutize(base_url, Mayhem::SitemapDiscovery::ROBOTS_PATH)
      end

      def base_url_for(website_url)
        normalized = Mayhem::Support::UrlNormalizer.normalize(website_url)
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
