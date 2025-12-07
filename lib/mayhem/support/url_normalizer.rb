# frozen_string_literal: true

require 'uri'

module Mayhem
  module Support
    module UrlNormalizer
      extend self

      TRACKING_PARAM_PREFIXES = ['utm_'].freeze
      GLOBAL_TRACKING_PARAMS = %w[
        fbclid
        gclid
        msclkid
        mc_cid
        mc_eid
        mkt_tok
        icid
        ref
        ref_src
        ref_url
      ].freeze
      HOST_TRACKING_PARAMS = {
        'pubmed.ncbi.nlm.nih.gov' => %w[fc ff v].freeze
      }.freeze

      # Normalize a link and ensure it is a valid http/https URL string or return nil.
      # link can be a String or object with to_s; base is optional website base URL.
      def normalize(link, base: nil)
        link_str = link.to_s.strip
        return nil if link_str.empty?

        base = base.to_s if base

        # protocol-relative
        link_str = "https:#{link_str}" if link_str.start_with?('//')

        uri = parse_uri_with_https_fallback(link_str)
        normalized = canonical_uri_string(uri)
        return normalized if normalized

        if base && !base.empty?
          begin
            joined = URI.join(base, link_str).to_s
            parsed = URI.parse(joined)
            normalized = canonical_uri_string(parsed)
            return normalized if normalized
          rescue StandardError
            return nil
          end
        end

        nil
      end

      private

      def canonical_uri_string(uri)
        return unless uri&.scheme && uri.host
        return unless uri.scheme.match?(/\Ahttps?\z/)

        cleaned = uri.dup
        cleaned.query = filtered_query(cleaned)
        cleaned.to_s
      end

      def filtered_query(uri)
        query = uri.query
        return nil if query.nil? || query.empty?

        params = decode_query(query)
        return query unless params

        host = uri.host&.downcase
        host_params = HOST_TRACKING_PARAMS.fetch(host, []) if host
        filtered = params.reject do |key, _|
          next false unless key

          downcased = key.downcase
          tracking_prefix?(downcased) ||
            GLOBAL_TRACKING_PARAMS.include?(downcased) ||
            host_params&.include?(downcased)
        end

        return nil if filtered.empty?

        URI.encode_www_form(filtered.sort_by { |key, value| [key, value] })
      rescue StandardError
        query
      end

      def decode_query(query)
        URI.decode_www_form(query, Encoding::UTF_8)
      rescue ArgumentError
        nil
      end

      def tracking_prefix?(param)
        TRACKING_PARAM_PREFIXES.any? { |prefix| param.start_with?(prefix) }
      end

      def parse_uri_with_https_fallback(str)
        URI.parse(str)
      rescue URI::InvalidURIError
        begin
          URI.parse("https://#{str}")
        rescue URI::InvalidURIError
          nil
        end
      end
    end
  end
end
