# frozen_string_literal: true

require 'seldon'
require 'stringio'
require 'time'
require 'zlib'

require_relative '../models/xml_sitemap'
require_relative '../models/sitemap_index'
require_relative '../models/url_set'
require_relative '../sitemap/discovery'

module Mayhem
  module Sitemaps
    class Refresh
      include Seldon::Loggable

      def initialize(http_client: nil)
        @http = http_client || Seldon::Support::HttpClient.new
      end

      def refresh(website, sitemap_urls)
        sitemap_urls.each do |url|
          refresh_sitemap(website, url)
        end
      end

      private

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
    end
  end
end
