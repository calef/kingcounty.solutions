# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require 'webmock/minitest'
require_relative '../../../lib/mayhem/news/rss_importer'
require 'mayhem/models/news'
require 'mayhem/models/organization'

class RssImporterTest < Minitest::Test
  def setup
    @org_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :organizations)
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @org_repo = Mayhem::Models::Organization.repo
    @news_repo = Mayhem::Models::News.repo
    @tmp_orgs = @org_repo.root.join('_organizations').to_s
    @tmp_posts = @news_repo.root.join('_posts').to_s
    Mayhem::Models::Organization.create!(
      {
        'title' => 'Test Org',
        'website_url' => 'https://example.com/',
        'news_rss_url' => 'https://example.com/feed.xml'
      },
      body: ''
    )

    @published_time = Time.now.utc - 24 * 60 * 60
    # simple feed with one item with relative link
    @feed_body = <<~XML
      <?xml version="1.0" encoding="UTF-8" ?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <title>Test Item</title>
            <link>/posts/1</link>
            <pubDate>#{@published_time.rfc2822}</pubDate>
            <description><![CDATA[<p>Original HTML</p>]]></description>
          </item>
        </channel>
      </rss>
    XML

    skip 'WebMock not available; skipping network-dependent test' if !defined?(WebMock) || WebMock.nil?

    VCR.use_cassette('rss_importer/test_feed') do
      stub_request(:get, 'https://example.com/feed.xml').to_return(status: 200, body: @feed_body, headers: {})
      stub_request(:get, 'https://example.com/posts/1').to_return(status: 200,
                                                                  body: '<html><body><article><p>Article body</p></article></body></html>')

      @importer = Mayhem::News::RssImporter.new(news_dir: @tmp_posts, sources_dir: @tmp_orgs)
    end
  end

  def teardown
    @org_repo_override.cleanup if @org_repo_override
    @news_repo_override.cleanup if @news_repo_override
  end

  def test_import_creates_post_with_valid_source_url
    @importer.run
    # run returns nil; verify output files and front matter instead of stats
    files = Dir.glob(File.join(@tmp_posts, '*.md'))

    assert_equal 1, files.length
    content = File.read(files.first)

    assert_includes content, 'source_url: https://example.com/posts/1'
  end

  def test_respects_locked_flag
    locked_record = Mayhem::Models::News.create!(
      {
        'title' => 'Locked version',
        'date' => @published_time.iso8601,
        'source_url' => 'https://example.com/locked',
        'feed_content' => 'Locked body',
        'locked' => true,
        'slug' => 'test-item'
      },
      body: 'Locked summary'
    )
    locked_path = locked_record.path.to_s

    locked_content = File.read(locked_path)
    @importer.run

    files = Dir.glob(File.join(@tmp_posts, '*.md'))
    assert_equal 1, files.length
    assert_equal locked_content, File.read(locked_path)
  end

  def test_register_post_tracks_link_and_guid_keys
    link = 'https://example.com/track'
    guid = 'guid-tracked'

    refute @importer.send(:duplicate_post?, link, guid)

    @importer.send(:register_post, link, guid)

    assert @importer.send(:duplicate_post?, link, guid)
    assert @importer.send(:duplicate_post?, link, nil)
    assert @importer.send(:duplicate_post?, nil, guid)
  end

  def test_duplicate_post_returns_false_when_no_keys
    assert_equal false, @importer.send(:duplicate_post?, nil, nil)
  end

  def test_extract_guid_text_uses_content_href_value_and_strips
    object_with_content = Struct.new(:content).new('  abc  ')
    object_with_href = Struct.new(:content, :href).new(nil, ' href ')
    object_with_value = Struct.new(:content, :href, :value).new(nil, nil, 'value  ')
    object_without_text = Struct.new(:content).new('   ')

    assert_equal 'abc', @importer.send(:extract_guid_text, object_with_content)
    assert_equal 'href', @importer.send(:extract_guid_text, object_with_href)
    assert_equal 'value', @importer.send(:extract_guid_text, object_with_value)
    assert_nil @importer.send(:extract_guid_text, object_without_text)
  end

  def test_item_guid_prefers_guid_then_id
    guid_value = Struct.new(:content).new('guid-value')
    id_value = Struct.new(:value).new('id-value')
    item_with_guid = Struct.new(:guid).new(guid_value)
    item_with_id = Struct.new(:guid, :id).new(nil, id_value)

    assert_equal 'guid-value', @importer.send(:item_guid, item_with_guid)
    assert_equal 'id-value', @importer.send(:item_guid, item_with_id)
  end
end
