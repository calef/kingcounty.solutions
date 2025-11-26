# frozen_string_literal: true

require 'test_helper'
require 'mayhem/feed_discovery'

FeedDiscovery = Mayhem::FeedDiscovery unless defined?(FeedDiscovery)

class SecondaryPageCollectorTest < Minitest::Test
  def test_collect_prefers_same_host_results
    html = <<~HTML
      <html>
        <body>
          <a href="/blog">Blog stories</a>
          <a href="https://external.example.com/blog" class="blog-link">Blog stories</a>
        </body>
      </html>
    HTML

    collector = FeedDiscovery::SecondaryPageCollector.new(html, 'https://example.org/home')

    assert_equal(
      ['https://example.org/blog', 'https://external.example.com/blog'],
      collector.collect
    )
  end

  def test_collect_deduplicates_urls
    html = <<~HTML
      <html>
        <body>
          <a href="/blog" class="news-link">Blog updates</a>
          <a href="/blog" id="rss">More blog posts</a>
        </body>
      </html>
    HTML

    collector = FeedDiscovery::SecondaryPageCollector.new(html, 'https://example.org')

    assert_equal(['https://example.org/blog'], collector.collect)
  end
end
