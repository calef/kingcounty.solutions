# frozen_string_literal: true

require 'stringio'
require 'uri'
require 'zlib'
require 'mayhem/logging'
require_relative '../support/http_client'
require_relative '../support/url_normalizer'
require_relative '../support/url_utils'

module Mayhem
  module SitemapDiscovery
    DEFAULT_PATHS = [
      '/sitemap.xml',
      '/sitemap_index.xml',
      '/sitemap-index.xml',
      '/sitemap.xml.gz'
    ].freeze
    ROBOTS_PATH = '/robots.txt'
    ROBOTS_MAX_BYTES = 262_144
    SITEMAP_MAX_BYTES = 1_048_576
    GZIP_SNIFF_BYTES = 65_536
    ACCEPT_ROBOTS = 'text/plain,*/*;q=0.1'
    ACCEPT_XML = 'application/xml,text/xml,application/rss+xml;q=0.9,*/*;q=0.1'

    class Finder
      include Mayhem::Loggable

      def initialize(http_client: nil)
        @http = http_client || Mayhem::Support::HttpClient.new( @logger)
      end

      def find(website_url)
        base_url = base_url_for(website_url)
        return [] unless base_url

        candidates = dedupe_candidates(
          candidates_from_robots(base_url) + default_candidates(base_url)
        )

        valid_sitemaps(candidates)
      rescue StandardError => e
        logger.warn "Sitemap discovery failed for #{website_url}: #{e.message}"
        []
      end

      private

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

      def candidates_from_robots(base_url)
        robots_url = Mayhem::Support::UrlUtils.absolutize(base_url, ROBOTS_PATH)
        return [] unless robots_url

        body = fetch_body(robots_url, accept: ACCEPT_ROBOTS, max_bytes: ROBOTS_MAX_BYTES)
        return [] if body.nil?

        extract_robots_sitemaps(body, base_url)
      end

      def extract_robots_sitemaps(body, base_url)
        candidates = body.to_s.each_line.filter_map do |line|
          match = line.match(/^\s*sitemap:\s*(\S+)/i)
          next unless match

          normalize_candidate(match[1], base_url)
        end

        dedupe_candidates(candidates)
      end

      def normalize_candidate(candidate, base_url)
        Mayhem::Support::UrlNormalizer.normalize(candidate, base: base_url)
      end

      def dedupe_candidates(candidates)
        seen = {}
        candidates.filter_map do |candidate|
          next if candidate.nil? || seen[candidate]

          seen[candidate] = true
          candidate
        end
      end

      def default_candidates(base_url)
        DEFAULT_PATHS.filter_map do |path|
          Mayhem::Support::UrlUtils.absolutize(base_url, path)
        end
      end

      def valid_sitemaps(candidates)
        candidates.each_with_object([]) do |candidate, collection|
          found = verify_candidate(candidate)
          collection << found if found
        end
      end

      def verify_candidate(candidate)
        response = @http.fetch(candidate, accept: ACCEPT_XML, max_bytes: SITEMAP_MAX_BYTES)
        return nil unless sitemap_like?(response[:body], response[:content_type])

        normalize_candidate(response[:final_url] || candidate, candidate)
      rescue StandardError => e
        logger.debug "Sitemap candidate failed for #{candidate}: #{e.message}"
        nil
      end

      def fetch_body(url, accept:, max_bytes:)
        response = @http.fetch(url, accept: accept, max_bytes: max_bytes)
        response[:body]
      rescue StandardError => e
        logger.debug "Robots fetch failed for #{url}: #{e.message}"
        nil
      end

      def sitemap_like?(body, content_type)
        snippet = normalized_snippet(body)
        return false unless snippet.match?(/<(urlset|sitemapindex)\b/i)

        return true if xml_content_type?(content_type)
        return true if snippet.lstrip.start_with?('<?xml', '<urlset', '<sitemapindex')

        true
      end

      def xml_content_type?(content_type)
        content_type.to_s.downcase.match?(/xml/)
      end

      def normalized_snippet(body)
        return '' if body.nil?

        raw = body.dup
        raw.force_encoding('BINARY')
        return normalize_string(raw) unless gzip_encoded?(raw)

        decompressed = gunzip_snippet(raw)
        normalize_string(decompressed || raw)
      end

      def gzip_encoded?(data)
        return false unless data && data.bytesize >= 2

        data.getbyte(0) == 0x1f && data.getbyte(1) == 0x8b
      end

      def gunzip_snippet(data)
        output = +''
        gz = nil
        gz = Zlib::GzipReader.new(StringIO.new(data))
        while output.bytesize < GZIP_SNIFF_BYTES
          chunk = gz.read([GZIP_SNIFF_BYTES - output.bytesize, 8192].min)
          break if chunk.nil? || chunk.empty?

          output << chunk
        end
        output
      rescue StandardError
        nil
      ensure
        gz&.close
      end

      def normalize_string(data)
        return '' if data.nil?

        str = data.dup
        str.force_encoding('BINARY')
        str = str[0, 4_000] if str.bytesize > 4_000
        str.encode('UTF-8', invalid: :replace, undef: :replace)
      rescue EncodingError
        str.force_encoding('UTF-8')
      end
    end
  end
end
