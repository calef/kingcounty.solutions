# frozen_string_literal: true

require_relative '../../test_helper'
require 'time'
require_relative '../../../lib/mayhem/news/rss_importer'

class RssImporterMethodsTest < Minitest::Test
  class FakeLogger
    attr_reader :errors, :warns, :infos, :debugs

    def initialize
      @errors = []
      @warns = []
      @infos = []
      @debugs = []
    end

    { error: :errors, warn: :warns, info: :infos, debug: :debugs }.each do |method, bucket|
      define_method(method) do |message|
        instance_variable_get("@#{bucket}") << message
      end
    end
  end

  class FakeHttpClient
    attr_accessor :response, :resolved_url, :fetch_called

    def initialize(resolved_url: nil)
      @resolved_url = resolved_url
      @response = nil
      @fetch_called = false
    end

    def fetch(_url, accept:, max_bytes:)
      @fetch_called = true
      response || { body: '', content_type: 'text/xml' }
    end

    def resolve_final_url(_url)
      resolved_url
    end
  end

  def setup
    @tmp_posts = Dir.mktmpdir
    @tmp_orgs = Dir.mktmpdir
    @logger = FakeLogger.new
    @fake_http = FakeHttpClient.new(resolved_url: 'https://pubmed.ncbi.nlm.nih.gov/final?utm_source=abc')
    @importer = Mayhem::News::RssImporter.new(
      news_dir: @tmp_posts,
      sources_dir: @tmp_orgs,
      http_client: @fake_http,
      logger: @logger
    )
    @fake_fetcher = Minitest::Mock.new
    @importer.instance_variable_set(:@content_fetcher, @fake_fetcher)
  end

  def teardown
    FileUtils.remove_entry(@tmp_posts)
    FileUtils.remove_entry(@tmp_orgs)
  end

  def test_published_at_prefers_pubdate_and_fallbacks
    item = Struct.new(:pubDate, :dc_date, :updated, :date).new(Time.utc(2025, 11, 25), nil, nil, nil)
    assert_equal Time.utc(2025, 11, 25), @importer.send(:published_at, item)

    fallback = Struct.new(:pubDate, :dc_date, :updated, :date).new(nil, nil, nil, Date.new(2025, 11, 22))
    assert_equal Date.new(2025, 11, 22).to_time, @importer.send(:published_at, fallback)
  end

  def test_determine_max_days_reads_config_value
    config_path = File.join(@tmp_posts, 'config.yml')
    File.write(config_path, "rss_max_item_age_days: 42\n")
    assert_equal 42, @importer.send(:determine_max_days, nil, config_path)
  end

  def test_item_content_html_prioritizes_fields
    item = Struct.new(:content_encoded, :description, :summary, :content)
                  .new('<p>encoded</p>', nil, nil, nil)
    assert_equal '<p>encoded</p>', @importer.send(:item_content_html, item)

    item = Struct.new(:content_encoded, :description, :summary, :content)
                  .new(nil, '<p>Description</p>', nil, nil)
    assert_equal '<p>Description</p>', @importer.send(:item_content_html, item)

    content_obj = Struct.new(:content).new('<p>inner</p>')
    item = Struct.new(:content_encoded, :description, :summary, :content)
                  .new(nil, nil, nil, content_obj)
    assert_equal '<p>inner</p>', @importer.send(:item_content_html, item)
  end

  def test_item_title_text_uses_content
    title = Struct.new(:content).new('Importance')
    item = Struct.new(:title).new(title)
    assert_equal 'Importance', @importer.send(:item_title_text, item)

    item = Struct.new(:title).new('Raw Title')
    assert_equal 'Raw Title', @importer.send(:item_title_text, item)
  end

  def test_item_link_url_handles_multiple_sources
    link = Struct.new(:href).new('https://example.com/link')
    item = Struct.new(:link).new(link)
    assert_equal 'https://example.com/link', @importer.send(:item_link_url, item)

    linkless = Struct.new(:links).new([Struct.new(:rel, :href).new('alternate', 'https://example.com/alt')])
    assert_equal 'https://example.com/alt', @importer.send(:item_link_url, linkless)

    url_item = Struct.new(:links, :url).new(nil, 'https://example.com/url')
    assert_equal 'https://example.com/url', @importer.send(:item_link_url, url_item)
  end

  def test_sanitize_feed_xml_removes_undeclared_prefixes_and_duplicate_declarations
    xml = <<~XML
      <?xml version="1.0"?>
      <?xml version="1.0"?>
      <rss xmlns:decl="http://example.com">
        <decl:item>keep</decl:item>
        <foo:value attr="bad">remove</foo:value>
      </rss>
    XML
    sanitized = @importer.send(:sanitize_feed_xml, xml, 'Test Feed', 'https://example.com/feed')
    assert_includes sanitized, '<decl:item>keep</decl:item>'
    refute_includes sanitized, 'foo:value'
    assert_equal 1, sanitized.scan(/<\?xml/).length
  end

  def test_feed_summary_line_formats_present_stats
    stats = { created: 1, duplicates: 2, locked: 1 }
    summary = @importer.send(:feed_summary_line, 'Source', 'https://source', stats)
    assert_includes summary, 'created=1'
    assert_includes summary, 'duplicates=2'
    assert_includes summary, 'locked=1'
  end

  def test_process_source_skips_sources_without_rss_url
    path = write_org_file('missing-rss.md', <<~MD)
      ---
      title: Missing RSS
      ---
    MD
    @fake_http.fetch_called = false
    assert_nil @importer.send(:process_source, path)
    refute @fake_http.fetch_called
  end

  def test_process_source_logs_error_when_feed_parser_returns_nil
    path = write_org_file('bad-feed.md', <<~MD)
      ---
      title: Bad Feed
      news_rss_url: https://example.com/feed
      ---
    MD
    @fake_http.response = { body: '<rss></rss>', content_type: 'application/rss+xml' }
    RSS::Parser.stub(:parse, nil) do
      @importer.send(:process_source, path)
    end
    assert_match(/Failed to parse RSS feed/, @logger.errors.last)
  end

  def test_build_existing_post_index_tracks_link_and_guid_keys
    write_post('2025-11-25-test.md', {
      'title' => 'Test',
      'source_url' => 'https://example.com/post',
      'original_content' => '<p>body</p>',
      'rss_guid' => 'guid-abc'
    })

    index = @importer.send(:build_existing_post_index)
    assert index.key?('link:https://example.com/post')
    assert index.key?('guid:guid-abc')
  end

  def test_process_item_records_missing_link
    stats = Hash.new(0)
    item = Object.new
    @importer.stub(:item_link_url, nil) do
      @importer.send(:process_item, item, 'Title', stats, { 'website' => 'https://example.com' })
    end
    assert_equal 1, stats[:missing_link]
  end

  def test_process_item_records_missing_title
    stats = Hash.new(0)
    item = Object.new
    @importer.stub(:item_link_url, 'https://example.com') do
      @importer.stub(:canonical_link, 'https://example.com') do
        @importer.stub(:item_title_text, '') do
          @importer.stub(:published_at, Time.now) do
            @importer.send(:process_item, item, 'Title', stats, {})
          end
        end
      end
    end
    assert_equal 1, stats[:missing_title]
  end

  def test_process_item_records_missing_publish_date
    stats = Hash.new(0)
    item = Object.new
    @importer.stub(:item_link_url, 'https://example.com') do
      @importer.stub(:canonical_link, 'https://example.com') do
        @importer.stub(:item_title_text, 'Title') do
          @importer.stub(:published_at, nil) do
            @importer.send(:process_item, item, 'Title', stats, {})
          end
        end
      end
    end
    assert_equal 1, stats[:missing_publish_date]
  end

  def test_process_item_records_stale_items
    stats = Hash.new(0)
    item = Object.new
    @importer.stub(:item_link_url, 'https://example.com') do
      @importer.stub(:canonical_link, 'https://example.com') do
        @importer.stub(:item_title_text, 'Title') do
          @importer.stub(:published_at, Time.now) do |*|
            @importer.stub(:stale_item?, true) do
              @importer.send(:process_item, item, 'Title', stats, {})
            end
          end
        end
      end
    end
    assert_equal 1, stats[:stale]
  end

  def test_unchanged_post_detects_matching_checksum
    normalized_html = Mayhem::Content::HtmlNormalizer.normalize('<p>body</p>', base_url: 'https://source')
    checksum = Mayhem::Content::HtmlNormalizer.checksum(normalized_html)
    path = write_post('2025-11-25-test.md', {
      'original_content' => '<p>body</p>',
      'original_content_checksum' => checksum,
      'source_url' => 'https://source',
      'published' => true
    }, '<p>body</p>')

    assert @importer.send(:unchanged_post?, path, normalized_html, checksum, 'https://source')
  end

  def test_canonical_link_calls_http_for_redirect_hosts
    url = 'https://pubmed.ncbi.nlm.nih.gov/item'
    @fake_http.resolved_url = 'https://pubmed.ncbi.nlm.nih.gov/item?utm_source=ignore'
    result = @importer.send(:canonical_link, url)
    expected = Mayhem::Support::UrlNormalizer.normalize(@fake_http.resolved_url)
    assert_equal expected, result
  end

  def test_fetch_article_body_returns_normalized_payload
    fetcher = Minitest::Mock.new
    fetcher.expect(:fetch, { html: 'body', canonical_url: 'https://example.com/canonical' }, ['https://example.com'])
    @importer.instance_variable_set(:@content_fetcher, fetcher)
    result = @importer.send(:fetch_article_body, 'https://example.com')
    assert_equal 'body', result[:html]
    assert_equal 'https://example.com/canonical', result[:canonical_url]
    fetcher.verify
  end

  private

  def write_post(filename, front_matter, body = '')
    path = File.join(@tmp_posts, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter.merge('original_content' => front_matter['original_content'] || ''), body))
    path
  end

  def write_org_file(filename, content)
    path = File.join(@tmp_orgs, filename)
    File.write(path, content)
    path
  end
end
