# frozen_string_literal: true

require 'stringio'
require 'time'
require 'set'
require 'zlib'

require_relative '../logging'
require_relative '../models/website'
require_relative '../models/xml_sitemap'
require_relative '../models/sitemap_index'
require_relative '../models/url_set'
require_relative '../sitemap/discovery'
require_relative '../support/http_client'
require_relative '../support/url_normalizer'

module Mayhem
  module Sitemaps
    class Refresh
      include Mayhem::Loggable

      def initialize(http_client: nil, sitemap_finder: nil)
        @http = http_client || Mayhem::Support::HttpClient.new
        @sitemap_finder = sitemap_finder || Mayhem::SitemapDiscovery::Finder.new(http_client: @http)
      end

      def run
        Mayhem::Models::Website.all.each do |website|
          refresh_website(website)
        end
      end

      private

      def refresh_website(website)
        unless website.robots_txt_url
          logger.debug "Skipping #{website.id} because robots_txt_url is unset"
          return
        end

        raw_urls = @sitemap_finder.find(website.homepage_url)
        sitemap_urls = prefer_gz_versions(normalize_url_list(raw_urls))

        update_website_xml_sitemap_urls(website, sitemap_urls)
        return if sitemap_urls.empty?

        refresh_sitemaps(website, sitemap_urls)
      rescue StandardError => e
        logger.warn "Failed to refresh sitemaps for #{website.id}: #{e.message}"
      end

      def update_website_xml_sitemap_urls(website, sitemap_urls)
        normalized_existing = normalize_url_list(website.xml_sitemap_urls)
        return if normalized_existing == sitemap_urls

        website['xml_sitemap_urls'] = sitemap_urls
        website.save!
        logger.info "Updated #{website.id} xml_sitemap_urls -> #{sitemap_urls.join(', ')}"
      end

      def refresh_sitemaps(website, sitemap_urls)
        sitemap_urls.each do |url|
          refresh_sitemap(website, url)
        end
      end

      def refresh_sitemap(website, url)
        sitemap_body = fetch_sitemap_body(url)
        return unless sitemap_body

        timestamp = Time.now.utc.iso8601
        model = case container_type(sitemap_body)
                when :sitemap_index
                  Mayhem::Models::SitemapIndex
                when :url_set
                  Mayhem::Models::UrlSet
                else
                  Mayhem::Models::XmlSitemap
                end
        record = model.find_by(url: url, website_id: website.id)
        if record
          update_sitemap_record(record, sitemap_body, website.id, timestamp)
        else
          create_sitemap_record(model, url, website.id, sitemap_body, timestamp)
        end
        logger.info "Saved sitemap #{url} for #{website.id}"
      rescue StandardError => e
        logger.warn "Failed to save sitemap #{url} for #{website.id}: #{e.message}"
      end

      def fetch_sitemap_body(url)
        response = @http.fetch(url, accept: Mayhem::SitemapDiscovery::ACCEPT_XML)
        decompress_sitemap(response[:body], url)
      rescue StandardError => e
        logger.warn "Failed to download sitemap #{url}: #{e.message}"
        nil
      end

      def create_sitemap_record(model, url, website_id, body, timestamp)
        model.create!(
          {
            'url' => url,
            'website_id' => website_id,
            'last_modified' => timestamp
          },
          body: body
        )
      end

      def update_sitemap_record(record, body, website_id, timestamp)
        record.body = body
        record['website_id'] = website_id
        record['last_modified'] = timestamp
        record.save!
      end

      def decompress_sitemap(raw, url)
        return nil if raw.nil?

        payload = raw.dup
        payload.force_encoding('BINARY')
        content = gzip_encoded?(payload) ? gunzip(payload, url) || payload : payload
        ensure_utf8(content)
      rescue StandardError => e
        logger.warn "Failed to decode sitemap #{url}: #{e.message}"
        ensure_utf8(payload || raw)
      end

      def gzip_encoded?(data)
        data.bytesize >= 2 && data.getbyte(0) == 0x1f && data.getbyte(1) == 0x8b
      end

      def gunzip(data, url)
        gz = Zlib::GzipReader.new(StringIO.new(data))
        gz.read
      rescue StandardError => e
        logger.warn "Failed to ungzip sitemap #{url}: #{e.message}"
        nil
      ensure
        gz&.close
      end

      def ensure_utf8(text)
        string = text.dup
        string.force_encoding('UTF-8')
        string.encode!('UTF-8', invalid: :replace, undef: :replace)
        string
      rescue EncodingError
        string.force_encoding('UTF-8')
        string
      end

      def container_type(body)
        normalized = body.to_s
        return :sitemap_index if normalized.match?(/<\s*sitemapindex\b/i)
        return :url_set if normalized.match?(/<\s*urlset\b/i)

        :generic
      end

      def normalize_url(value, base_url = nil)
        return nil if value.nil?

        Mayhem::Support::UrlNormalizer.normalize(value, base: base_url)
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
