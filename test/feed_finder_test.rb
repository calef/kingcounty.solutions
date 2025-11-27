# frozen_string_literal: true

require 'test_helper'
require 'mayhem/feed_discovery'

FeedDiscovery = Mayhem::FeedDiscovery unless defined?(FeedDiscovery)

class FeedFinderTest < Minitest::Test
  class FakeHttp
    attr_reader :requests

    def initialize(responses)
      @responses = responses
      @requests = []
    end

    def fetch(url, accept:, max_bytes:)
      @requests << { url: url, accept: accept, max_bytes: max_bytes }
      response = @responses.fetch(url) { raise "Unexpected request for #{url}" }
      response.respond_to?(:call) ? response.call : response
    end
  end

  def test_finds_feed_url_from_alternate_link
    html = <<~HTML
      <html>
        <head>
          <link rel="alternate" type="application/rss+xml" href="/feed.xml" />
        </head>
      </html>
    HTML
    responses = {
      'https://example.org' => {
        body: html,
        content_type: 'text/html',
        final_url: 'https://example.org'
      },
      'https://example.org/feed.xml' => {
        body: '<rss></rss>',
        content_type: 'application/rss+xml',
        final_url: 'https://example.org/feed.xml'
      }
    }

    http = FakeHttp.new(responses)
    finder = FeedDiscovery::FeedFinder.new(http)

    result = finder.find('https://example.org')

    assert_equal 'https://example.org/feed.xml', result.rss_url
    assert_nil result.ical_url
    assert_equal(['https://example.org', 'https://example.org/feed.xml'],
                 http.requests.map { |req| req[:url] })
    assert_equal FeedDiscovery::ACCEPT_HTML, http.requests.first[:accept]
    assert_equal FeedDiscovery::ACCEPT_FEED, http.requests.last[:accept]
  end

  def test_probes_secondary_pages_when_direct_feed_is_missing
    html = '<a href="/news">Latest news</a>'
    news_html = <<~HTML
      <html>
        <head>
          <link rel="alternate" type="application/atom+xml" href="/news/feed.atom" />
        </head>
      </html>
    HTML
    responses = {
      'https://example.org' => {
        body: html,
        content_type: 'text/html',
        final_url: 'https://example.org'
      },
      'https://example.org/news' => {
        body: news_html,
        content_type: 'text/html',
        final_url: 'https://example.org/news'
      },
      'https://example.org/news/feed.atom' => {
        body: '<feed></feed>',
        content_type: 'application/atom+xml',
        final_url: 'https://example.org/news/feed.atom'
      }
    }

    http = FakeHttp.new(responses)
    finder = FeedDiscovery::FeedFinder.new(http)

    result = finder.find('https://example.org')

    assert_equal 'https://example.org/news/feed.atom', result.rss_url
    assert_equal(['https://example.org',
                  'https://example.org/news',
                  'https://example.org/news',
                  'https://example.org/news/feed.atom'],
                 http.requests.map { |req| req[:url] })
  end

  def test_finds_ical_link_when_available
    html = <<~HTML
      <html>
        <head>
          <link rel="alternate" type="text/calendar" href="/calendar.ics" />
        </head>
      </html>
    HTML
    responses = {
      'https://example.org' => {
        body: html,
        content_type: 'text/html',
        final_url: 'https://example.org'
      },
      'https://example.org/calendar.ics' => {
        body: 'BEGIN:VCALENDAR\\r\\nEND:VCALENDAR',
        content_type: 'text/calendar',
        final_url: 'https://example.org/calendar.ics'
      }
    }

    http = FakeHttp.new(responses)
    finder = FeedDiscovery::FeedFinder.new(http)

    result = finder.find('https://example.org')

    assert_nil result.rss_url
    assert_equal 'https://example.org/calendar.ics', result.ical_url
  end

  def test_find_returns_nil_when_http_errors
    responses = {
      'https://example.org' => lambda do
        raise StandardError, 'boom'
      end
    }
    http = FakeHttp.new(responses)
    finder = FeedDiscovery::FeedFinder.new(http, logger: error_level_logger)

    assert_nil finder.find('https://example.org')
  end

  def test_verify_feed_accepts_json_snippet_with_rss_key
    responses = {
      'https://example.org/feed.json' => {
        body: '{"status":"ok","rss":true}',
        content_type: 'application/json',
        final_url: 'https://example.org/feed.json'
      }
    }
    http = FakeHttp.new(responses)
    finder = FeedDiscovery::FeedFinder.new(http)

    result = finder.send(:verify_feed, 'https://example.org/feed.json')

    assert_equal [:rss, 'https://example.org/feed.json'], result
  end

  def test_feed_like_checks_content_type_and_body
    finder = FeedDiscovery::FeedFinder.new(FakeHttp.new({}))

    assert finder.send(:feed_like?, '<rss></rss>', 'application/rss+xml')
    assert finder.send(:feed_like?, '<feed></feed>', 'text/html')
    refute finder.send(:feed_like?, '<html></html>', 'text/html')
  end

  def test_calendar_like_checks_content_type_and_body
    finder = FeedDiscovery::FeedFinder.new(FakeHttp.new({}))

    assert finder.send(:calendar_like?, 'BEGIN:VCALENDAR', 'text/calendar')
    assert finder.send(:calendar_like?, 'BEGIN:VCALENDAR', 'text/plain')
    refute finder.send(:calendar_like?, '<html></html>', 'text/html')
  end

  def test_decode_html_recovers_from_invalid_bytes
    finder = FeedDiscovery::FeedFinder.new(FakeHttp.new({}))
    binary = "\xFF\xFE\xC3".dup
    binary.force_encoding('BINARY')

    decoded = finder.send(:decode_html, binary)

    assert_equal Encoding::UTF_8, decoded.encoding
    refute_empty decoded
  end

  private

  def error_level_logger
    original = ENV.fetch('LOG_LEVEL', nil)
    ENV['LOG_LEVEL'] = 'ERROR'
    Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'ERROR')
  ensure
    ENV['LOG_LEVEL'] = original
  end
end
