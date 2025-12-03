# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require 'webmock/minitest'
require 'tmpdir'
require_relative '../../lib/mayhem/news/rss_importer'

class RssImporterTest < Minitest::Test
  def setup
    @tmp_posts = Dir.mktmpdir
    @tmp_orgs = Dir.mktmpdir
    # create a minimal organization file with website and rss
    org = <<~MD
      ---
      title: Test Org
      website: https://example.com/
      news_rss_url: https://example.com/feed.xml
      ---
    MD
    File.write(File.join(@tmp_orgs, 'test-org.md'), org)

    # simple feed with one item with relative link
    @feed_body = <<~XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <title>Test Item</title>
            <link>/posts/1</link>
            <pubDate>#{Time.now.rfc2822}</pubDate>
            <description><![CDATA[<p>Original HTML</p>]]></description>
          </item>
        </channel>
      </rss>
    XML

    if !defined?(WebMock) || WebMock.nil?
      skip 'WebMock not available; skipping network-dependent test'
    end

    VCR.use_cassette('rss_importer/test_feed') do
      stub_request(:get, 'https://example.com/feed.xml').to_return(status: 200, body: @feed_body, headers: {})
      stub_request(:get, 'https://example.com/posts/1').to_return(status: 200, body: '<html><body><article><p>Article body</p></article></body></html>')

      @importer = Mayhem::News::RssImporter.new(news_dir: @tmp_posts, sources_dir: @tmp_orgs)
    end
  end

  def teardown
    FileUtils.remove_entry(@tmp_posts)
    FileUtils.remove_entry(@tmp_orgs)
  end

  def test_import_creates_post_with_valid_source_url
    stats = @importer.run
    # run returns nil; verify output files and front matter instead of stats
    files = Dir.glob(File.join(@tmp_posts, '*.md'))
    assert_equal 1, files.length
    content = File.read(files.first)
    assert_includes content, 'source_url: https://example.com/posts/1'
  end
end
