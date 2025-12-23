# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require 'mayhem/sitemap/discovery'
require 'mayhem/support/http_client'
require 'stringio'
require 'zlib'

class SitemapDiscoveryTest < Minitest::Test
  class FakeHttpClient
    def initialize(responses)
      @responses = responses
    end

    def fetch(url, accept:, max_bytes:)
      response = @responses.fetch(url) do
        raise Mayhem::Support::HttpClient::NotFoundError.new(
          url: url,
          origin_url: url,
          operation: 'content_fetch',
          status: 404
        )
      end

      raise response if response.is_a?(StandardError)

      response
    end
  end

  class NullLogger
    def warn(_message); end

    def debug(_message); end
  end

  def urlset_xml
    '<?xml version="1.0" encoding="UTF-8"?><urlset></urlset>'
  end

  def sitemapindex_xml
    '<?xml version="1.0" encoding="UTF-8"?><sitemapindex></sitemapindex>'
  end

  def finder_for(responses)
    Mayhem::SitemapDiscovery::Finder.new(
      http_client: FakeHttpClient.new(responses),
      logger: NullLogger.new
    )
  end

  def gzip(body)
    buffer = StringIO.new
    Zlib::GzipWriter.wrap(buffer) { |gz| gz.write(body) }
    buffer.string
  end

  def test_finds_sitemap_from_robots
    responses = {
      'https://example.com/robots.txt' => {
        body: "User-agent: *\nSitemap: https://example.com/sitemap.xml\n",
        content_type: 'text/plain',
        final_url: 'https://example.com/robots.txt'
      },
      'https://example.com/sitemap.xml' => {
        body: urlset_xml,
        content_type: 'application/xml',
        final_url: 'https://example.com/sitemap.xml'
      }
    }

    finder = finder_for(responses)

    assert_equal ['https://example.com/sitemap.xml'], finder.find('https://example.com')
  end

  def test_robots_multiple_entries_selects_first_valid
    responses = {
      'https://example.com/robots.txt' => {
        body: <<~TXT,
          User-agent: *
          Sitemap: https://example.com/not-sitemap.xml
          Sitemap: /sitemap.xml
        TXT
        content_type: 'text/plain',
        final_url: 'https://example.com/robots.txt'
      },
      'https://example.com/not-sitemap.xml' => {
        body: '<html>no sitemap</html>',
        content_type: 'application/xml',
        final_url: 'https://example.com/not-sitemap.xml'
      },
      'https://example.com/sitemap.xml' => {
        body: urlset_xml,
        content_type: 'application/xml',
        final_url: 'https://example.com/sitemap.xml'
      }
    }

    finder = finder_for(responses)

    assert_equal ['https://example.com/sitemap.xml'], finder.find('https://example.com')
  end

  def test_robots_missing_falls_back_to_defaults
    responses = {
      'https://example.com/robots.txt' => Mayhem::Support::HttpClient::NotFoundError.new(
        url: 'https://example.com/robots.txt',
        origin_url: 'https://example.com/robots.txt',
        operation: 'content_fetch',
        status: 404
      ),
      'https://example.com/sitemap.xml' => {
        body: urlset_xml,
        content_type: 'application/xml',
        final_url: 'https://example.com/sitemap.xml'
      }
    }

    finder = finder_for(responses)

    assert_equal ['https://example.com/sitemap.xml'], finder.find('https://example.com')
  end

  def test_robots_timeout_falls_back_to_defaults
    responses = {
      'https://example.com/robots.txt' => Net::ReadTimeout.new('timeout'),
      'https://example.com/sitemap.xml' => {
        body: urlset_xml,
        content_type: 'application/xml',
        final_url: 'https://example.com/sitemap.xml'
      }
    }

    finder = finder_for(responses)

    assert_equal ['https://example.com/sitemap.xml'], finder.find('https://example.com')
  end

  def test_falls_back_to_index_when_default_missing
    responses = {
      'https://example.com/robots.txt' => Mayhem::Support::HttpClient::NotFoundError.new(
        url: 'https://example.com/robots.txt',
        origin_url: 'https://example.com/robots.txt',
        operation: 'content_fetch',
        status: 404
      ),
      'https://example.com/sitemap.xml' => Mayhem::Support::HttpClient::NotFoundError.new(
        url: 'https://example.com/sitemap.xml',
        origin_url: 'https://example.com/sitemap.xml',
        operation: 'content_fetch',
        status: 404
      ),
      'https://example.com/sitemap_index.xml' => {
        body: sitemapindex_xml,
        content_type: 'application/xml',
        final_url: 'https://example.com/sitemap_index.xml'
      }
    }

    finder = finder_for(responses)

    assert_equal ['https://example.com/sitemap_index.xml'], finder.find('https://example.com')
  end

  def test_rejects_non_sitemap_candidate
    responses = {
      'https://example.com/robots.txt' => {
        body: "User-agent: *\nSitemap: https://example.com/not-sitemap.xml\n",
        content_type: 'text/plain',
        final_url: 'https://example.com/robots.txt'
      },
      'https://example.com/not-sitemap.xml' => {
        body: '<html>no sitemap</html>',
        content_type: 'application/xml',
        final_url: 'https://example.com/not-sitemap.xml'
      },
      'https://example.com/sitemap.xml' => {
        body: urlset_xml,
        content_type: 'application/xml',
        final_url: 'https://example.com/sitemap.xml'
      }
    }

    finder = finder_for(responses)

    assert_equal ['https://example.com/sitemap.xml'], finder.find('https://example.com')
  end

  def test_accepts_sitemap_with_text_html_content_type
    responses = {
      'https://example.com/robots.txt' => Mayhem::Support::HttpClient::NotFoundError.new(
        url: 'https://example.com/robots.txt',
        origin_url: 'https://example.com/robots.txt',
        operation: 'content_fetch',
        status: 404
      ),
      'https://example.com/sitemap.xml' => {
        body: urlset_xml,
        content_type: 'text/html; charset=utf-8',
        final_url: 'https://example.com/sitemap.xml'
      }
    }

    finder = finder_for(responses)

    assert_equal ['https://example.com/sitemap.xml'], finder.find('https://example.com')
  end

  def test_accepts_gzipped_sitemap_body
    responses = {
      'https://example.com/robots.txt' => Mayhem::Support::HttpClient::NotFoundError.new(
        url: 'https://example.com/robots.txt',
        origin_url: 'https://example.com/robots.txt',
        operation: 'content_fetch',
        status: 404
      ),
      'https://example.com/sitemap.xml.gz' => {
        body: gzip(urlset_xml),
        content_type: 'application/octet-stream',
        final_url: 'https://example.com/sitemap.xml.gz'
      }
    }

    finder = finder_for(responses)

    assert_equal ['https://example.com/sitemap.xml.gz'], finder.find('https://example.com')
  end

  def test_follows_redirect_and_returns_final_url
    responses = {
      'https://example.com/robots.txt' => Mayhem::Support::HttpClient::NotFoundError.new(
        url: 'https://example.com/robots.txt',
        origin_url: 'https://example.com/robots.txt',
        operation: 'content_fetch',
        status: 404
      ),
      'https://example.com/sitemap.xml' => {
        body: urlset_xml,
        content_type: 'application/xml',
        final_url: 'https://example.com/sitemaps/main.xml'
      }
    }

    finder = finder_for(responses)

    assert_equal ['https://example.com/sitemaps/main.xml'], finder.find('https://example.com')
  end
end
