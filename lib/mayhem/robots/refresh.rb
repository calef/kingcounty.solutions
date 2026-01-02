# frozen_string_literal: true

require 'seldon'
require 'time'
require 'uri'

require_relative '../models/robots_txt'
require_relative '../sitemap/discovery'

module Mayhem
  module Robots
    class Refresh
      include Seldon::Loggable

      def initialize(http_client: nil)
        @http = http_client || Seldon::Support::HttpClient.new
      end

      def refresh(website)
        record = find_robots_record(website)
        robots_url = record&.url || compute_default_robots_url(website.homepage_url)
        unless robots_url
          logger.debug "Skipping #{website.id} because robots_txt_url could not be determined"
          return nil
        end
        robots_url = normalize_url(robots_url)
        unless robots_url
          logger.debug "Skipping #{website.id} because robots_txt_url could not be normalized"
          return nil
        end

        response = @http.fetch(robots_url, accept: Mayhem::SitemapDiscovery::ACCEPT_ROBOTS)
        body = ensure_utf8(response[:body]).strip
        final_url = response[:final_url] || robots_url
        store_robots(website, final_url, body, record)
        final_url
      rescue StandardError => e
        logger.warn "Failed to refresh robots for #{website.id}: #{e.message}"
        nil
      end

      private

      def find_robots_record(website)
        Mayhem::Models::RobotsTxt.find_by(website_id: website.id)
      end

      def compute_default_robots_url(homepage_url)
        return nil unless homepage_url

        base_url = base_url_for(homepage_url)
        return nil unless base_url

        Seldon::Support::UrlUtils.absolutize(base_url, Mayhem::SitemapDiscovery::ROBOTS_PATH)
      end

      def base_url_for(url)
        normalized = Seldon::Support::UrlNormalizer.normalize(url)
        return nil unless normalized

        uri = URI.parse(normalized)
        return nil unless uri.scheme && uri.host

        base = "#{uri.scheme}://#{uri.host}"
        base += ":#{uri.port}" if uri.port && uri.port != uri.default_port
        base
      rescue URI::Error
        nil
      end

      def normalize_url(value)
        Seldon::Support::UrlNormalizer.normalize(value)
      rescue StandardError
        nil
      end

      def store_robots(website, url, body, record)
        timestamp = Time.now.utc.iso8601
        if record
          update_record(record, url, body, website.id, timestamp)
        else
          create_record(url, website.id, body, timestamp)
        end
      end

      def create_record(url, website_id, body, timestamp)
        Mayhem::Models::RobotsTxt.create!(
          {
            'url' => url,
            'website_id' => website_id,
            'last_modified' => timestamp
          },
          body: body
        )
      end

      def update_record(record, url, body, website_id, timestamp)
        record.body = body
        record['url'] = url
        record['website_id'] = website_id
        record['last_modified'] = timestamp
        record.save!
      end

      def ensure_utf8(text)
        string = text.to_s.dup
        string.force_encoding('UTF-8')
        string.encode!('UTF-8', invalid: :replace, undef: :replace)
        string
      rescue EncodingError
        string.force_encoding('UTF-8')
        string
      end
    end
  end
end
