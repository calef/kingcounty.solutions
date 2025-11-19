# frozen_string_literal: true

require 'test_helper'
require 'news_rss'

class CandidateCollectorTest < Minitest::Test
  def test_collect_ranks_link_candidates_and_honors_base_href
    html = <<~HTML
      <html>
        <head>
          <base href="/base/" />
          <link rel="alternate" type="application/rss+xml" title="Main feed" href="feed.xml" />
        </head>
        <body>
          <a href="/rss.xml" class="rss-link">RSS</a>
          <a href="mailto:info@example.org">Contact</a>
        </body>
      </html>
    HTML

    collector = NewsRSS::CandidateCollector.new(html, 'https://example.org/posts/index.html')

    assert_equal(
      ['https://example.org/base/feed.xml', 'https://example.org/rss.xml'],
      collector.collect
    )
  end

  def test_collect_includes_wordpress_guess
    html = '<html><body><p>Powered by WordPress CMS</p></body></html>'

    collector = NewsRSS::CandidateCollector.new(html, 'https://example.org/blog/post')

    assert_equal(['https://example.org/feed/'], collector.collect)
  end

  def test_collect_uses_fallback_scan_when_no_nodes_present
    html = '<div>Legacy markup href="feeds/updates-rss.xml"</div>'

    collector = NewsRSS::CandidateCollector.new(html, 'https://example.org')

    assert_equal(['https://example.org/feeds/updates-rss.xml'], collector.collect)
  end
end
