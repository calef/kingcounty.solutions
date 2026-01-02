# frozen_string_literal: true

require 'digest'
require 'nokogiri'
require 'seldon'
require 'uri'

module Mayhem
  module Content
    module HtmlNormalizer
      module_function

      URL_ATTRIBUTES = %w[href src].freeze
      TRACKING_PARAM_PREFIXES = %w[utm_ mc_].freeze
      TRACKING_PARAM_NAMES = %w[fbclid gclid gclsrc mc_cid mc_eid].freeze
      DEFAULT_ALLOWED_ATTRIBUTES = {
        'img' => %w[src]
      }.freeze

      def normalize(html, base_url: nil)
        return '' if html.nil?

        html_string = html.to_s
        return html_string if html_string.strip.empty?

        fragment = Nokogiri::HTML::DocumentFragment.parse(html_string)
        fragment.traverse do |node|
          next unless node.element?

          allowed_attributes = allowed_attributes_for(node)

          node.attribute_nodes.each do |attr|
            attr_name = attr.name.downcase
            next if allowed_attributes.include?(attr_name)

            attr.remove
          end

          URL_ATTRIBUTES.each do |attribute|
            next unless node.has_attribute?(attribute)
            next unless allowed_attributes.include?(attribute)

            normalized_value = normalize_url_attribute(node[attribute], base_url)
            next unless normalized_value

            node[attribute] = normalized_value
          end
        end
        fragment.to_html
      rescue StandardError
        html.to_s
      end

      def allowed_attributes_for(node)
        DEFAULT_ALLOWED_ATTRIBUTES.fetch(node.name.downcase, [])
      end

      def checksum(normalized_html)
        Digest::SHA1.hexdigest(normalized_html.to_s)
      end

      def normalize_url_attribute(value, base_url)
        normalized = Seldon::Support::UrlNormalizer.normalize(value, base: base_url)
        return value unless normalized

        canonicalize_url(normalized)
      end

      def canonicalize_url(url)
        uri = URI.parse(url)
        return url unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)

        uri.scheme = uri.scheme.downcase if uri.scheme
        uri.host = uri.host.downcase if uri.host

        if uri.query
          params = URI.decode_www_form(uri.query)
          params.reject! { |key, _| tracking_param?(key) }
          params.sort_by! { |key, value| [key, value.to_s] }
          uri.query = params.empty? ? nil : URI.encode_www_form(params)
        end

        uri.fragment = nil if uri.fragment.to_s.strip.empty?
        uri.to_s
      rescue StandardError
        url
      end

      def tracking_param?(key)
        normalized_key = key.to_s.downcase
        return true if TRACKING_PARAM_NAMES.include?(normalized_key)

        TRACKING_PARAM_PREFIXES.any? do |prefix|
          normalized_key.start_with?(prefix)
        end
      end
    end
  end
end
