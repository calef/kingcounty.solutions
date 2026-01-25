# frozen_string_literal: true

require_relative '../../test_helper'
require 'fileutils'
require 'mayhem/models/news'
require 'mayhem/models/organization'
require 'seldon'
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

    def trace(_message); end
  end

  class FakeHttpClient
    attr_accessor :response, :resolved_url, :fetch_called

    def initialize(resolved_url: nil)
      @resolved_url = resolved_url
      @response = nil
      @fetch_called = false
    end

    def fetch(_url, accept:)
      @fetch_called = true
      response || { body: '', content_type: 'text/xml' }
    end

    def resolve_final_url(_url)
      resolved_url
    end
  end

  def setup
    @org_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :organizations)
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @tmp_posts = Mayhem::Models::News.repo.root.join('_posts').to_s
    @tmp_orgs = Mayhem::Models::Organization.repo.root.join('_organizations').to_s
    @logger = FakeLogger.new
    Seldon::Logging.logger = @logger
    @fake_http = FakeHttpClient.new(resolved_url: 'https://pubmed.ncbi.nlm.nih.gov/final?utm_source=abc')
    @item_parser = Mayhem::News::RssImporter::ItemParser.new()
    @canonicalizer = Mayhem::News::RssImporter::Canonicalizer.new(http_client: @fake_http)
    @post_writer = Mayhem::News::RssImporter::PostWriter.new(news_model: Mayhem::Models::News)
    @duplicate_tracker = Mayhem::News::RssImporter::DuplicateTracker.new(news_model: Mayhem::Models::News)
    @fake_fetcher = Minitest::Mock.new
    @item_processor = build_item_processor(content_fetcher: @fake_fetcher)
    @feed_sanitizer = Mayhem::News::RssImporter::FeedSanitizer.new()
    @feed_runner = Mayhem::News::RssImporter::FeedRunner.new(http_client: @fake_http,
      feed_sanitizer: @feed_sanitizer,
      item_processor: @item_processor
    )
  end

  def teardown
    @org_repo_override.cleanup if @org_repo_override
    @news_repo_override.cleanup if @news_repo_override
    Seldon::Logging.reset_logger
  end

  def test_published_at_prefers_pubdate_and_fallbacks
    item = Struct.new(:pubDate, :dc_date, :updated, :date).new(Time.utc(2025, 11, 25), nil, nil, nil)
    assert_equal Time.utc(2025, 11, 25), @item_parser.published_at(item)

    fallback = Struct.new(:pubDate, :dc_date, :updated, :date).new(nil, nil, nil, Date.new(2025, 11, 22))
    assert_equal Date.new(2025, 11, 22).to_time, @item_parser.published_at(fallback)
  end

  def test_determine_max_days_reads_config_value
    config_path = File.join(@tmp_posts, 'config.yml')
    FileUtils.mkdir_p(File.dirname(config_path))
    File.write(config_path, "rss_max_item_age_days: 42\n")
    config = Mayhem::News::RssImporter::Config.new(config_path: config_path)
    assert_equal 42, config.max_item_age_days
  end

  def test_item_content_html_prioritizes_fields
    item = Struct.new(:content_encoded, :description, :summary, :content)
                  .new('<p>encoded</p>', nil, nil, nil)
    assert_equal '<p>encoded</p>', @item_parser.content_html(item)

    item = Struct.new(:content_encoded, :description, :summary, :content)
                  .new(nil, '<p>Description</p>', nil, nil)
    assert_equal '<p>Description</p>', @item_parser.content_html(item)

    content_obj = Struct.new(:content).new('<p>inner</p>')
    item = Struct.new(:content_encoded, :description, :summary, :content)
                  .new(nil, nil, nil, content_obj)
    assert_equal '<p>inner</p>', @item_parser.content_html(item)
  end

  def test_item_title_text_uses_content
    title = Struct.new(:content).new('Importance')
    item = Struct.new(:title).new(title)
    assert_equal 'Importance', @item_parser.title_text(item)

    item = Struct.new(:title).new('Raw Title')
    assert_equal 'Raw Title', @item_parser.title_text(item)
  end

  def test_item_link_url_handles_multiple_sources
    link = Struct.new(:href).new('https://example.com/link')
    item = Struct.new(:link).new(link)
    assert_equal 'https://example.com/link', @item_parser.link_url(item)

    linkless = Struct.new(:links).new([Struct.new(:rel, :href).new('alternate', 'https://example.com/alt')])
    assert_equal 'https://example.com/alt', @item_parser.link_url(linkless)

    url_item = Struct.new(:links, :url).new(nil, 'https://example.com/url')
    assert_equal 'https://example.com/url', @item_parser.link_url(url_item)
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
    sanitized = @feed_sanitizer.sanitize(xml, 'Test Feed', 'https://example.com/feed')
    assert_includes sanitized, '<decl:item>keep</decl:item>'
    refute_includes sanitized, 'foo:value'
    assert_equal 1, sanitized.scan(/<\?xml/).length
  end

  def test_feed_summary_line_formats_present_stats
    stats = Mayhem::News::RssImporter::FeedStats.new
    stats.increment(:created)
    stats.increment(:duplicates)
    stats.increment(:duplicates)
    stats.increment(:locked)
    summary = stats.summary_line('Source', 'https://source')
    assert_includes summary, 'created=1'
    assert_includes summary, 'duplicates=2'
    assert_includes summary, 'locked=1'
  end

  def test_process_source_skips_sources_without_rss_url
    source = write_org_record('title' => 'Missing RSS')
    @fake_http.fetch_called = false
    assert_nil @feed_runner.process(source)
    refute @fake_http.fetch_called
  end

  def test_process_source_logs_error_when_feed_parser_returns_nil
    source = write_org_record(
      'title' => 'Bad Feed',
      'news_rss_url' => 'https://example.com/feed'
    )
    @fake_http.response = { body: '<rss></rss>', content_type: 'application/rss+xml' }
    RSS::Parser.stub(:parse, nil) do
      @feed_runner.process(source)
    end
    assert_match(/Failed to parse RSS feed/, @logger.errors.last)
  end

  def test_build_existing_post_index_tracks_link_and_guid_keys
    write_post({
      'title' => 'Test',
      'date' => Time.utc(2025, 11, 25).iso8601,
      'source_url' => 'https://example.com/post',
      'feed_content' => '<p>body</p>',
      'rss_guid' => 'guid-abc'
    })

    tracker = Mayhem::News::RssImporter::DuplicateTracker.new(news_model: Mayhem::Models::News)
    assert tracker.duplicate?('https://example.com/post', 'guid-abc')
  end

  def test_process_item_records_missing_link
    stats = Mayhem::News::RssImporter::FeedStats.new
    item = Object.new
    source = build_source_record(website_url: 'https://example.com')
    @item_parser.stub(:link_url, nil) do
      @item_processor.process(item, 'Title', source, stats)
    end
    assert_equal 1, stats[:missing_link]
  end

  def test_process_item_records_missing_title
    stats = Mayhem::News::RssImporter::FeedStats.new
    item = Object.new
    source = build_source_record
    @item_parser.stub(:link_url, 'https://example.com') do
      @canonicalizer.stub(:canonical_link, 'https://example.com') do
        @item_parser.stub(:title_text, '') do
          @item_parser.stub(:published_at, Time.now) do
            @item_processor.process(item, 'Title', source, stats)
          end
        end
      end
    end
    assert_equal 1, stats[:missing_title]
  end

  def test_process_item_records_missing_publish_date
    stats = Mayhem::News::RssImporter::FeedStats.new
    item = Object.new
    source = build_source_record
    @item_parser.stub(:link_url, 'https://example.com') do
      @canonicalizer.stub(:canonical_link, 'https://example.com') do
        @item_parser.stub(:title_text, 'Title') do
          @item_parser.stub(:published_at, nil) do
            @item_processor.process(item, 'Title', source, stats)
          end
        end
      end
    end
    assert_equal 1, stats[:missing_publish_date]
  end

  def test_process_item_records_stale_items
    stats = Mayhem::News::RssImporter::FeedStats.new
    item = Object.new
    source = build_source_record
    @item_parser.stub(:link_url, 'https://example.com') do
      @canonicalizer.stub(:canonical_link, 'https://example.com') do
        @item_parser.stub(:title_text, 'Title') do
          @item_parser.stub(:published_at, Time.now) do |*|
            @item_processor.stub(:stale_item?, true) do
              @item_processor.process(item, 'Title', source, stats)
            end
          end
        end
      end
    end
    assert_equal 1, stats[:stale]
  end

  def test_process_item_records_empty_content_when_fetch_returns_blank
    stats = Mayhem::News::RssImporter::FeedStats.new
    item = Object.new
    source = build_source_record
    link_url = 'https://example.com/article'
    normalized = Seldon::Support::UrlNormalizer.normalize(link_url, base: source&.website_url)
    fetcher = Minitest::Mock.new
    fetcher.expect(:fetch, { html: '', canonical_url: nil }, [link_url])
    duplicate_tracker = Minitest::Mock.new
    duplicate_tracker.expect(:duplicate?, false, [normalized, 'guid-1'])
    processor = build_item_processor(
      content_fetcher: fetcher,
      item_parser: build_item_parser(
        link_url: link_url,
        guid: 'guid-1',
        title_text: 'Title',
        published_at: Time.now,
        content_html: ''
      ),
      duplicate_tracker: duplicate_tracker,
      post_writer: Minitest::Mock.new
    )

    result = processor.process(item, 'Source', source, stats)

    assert_nil result
    assert_equal 1, stats[:empty_content]
    fetcher.verify
    duplicate_tracker.verify
  end

  def test_process_item_marks_not_found_and_writes_unpublished_post
    stats = Mayhem::News::RssImporter::FeedStats.new
    item = Object.new
    source = build_source_record
    link_url = 'https://example.com/article'
    normalized = Seldon::Support::UrlNormalizer.normalize(link_url, base: source&.website_url)
    published_at = Time.now
    fetcher = Minitest::Mock.new
    fetcher.expect(:fetch, { html: '', canonical_url: nil, not_found: true }, [link_url])
    duplicate_tracker = Minitest::Mock.new
    duplicate_tracker.expect(:duplicate?, false, [normalized, 'guid-404'])
    duplicate_tracker.expect(:register, nil, [normalized, 'guid-404'])
    post_writer = Minitest::Mock.new
    post_writer.expect(
      :write,
      :created,
      ['Source', 'Missing Article', normalized, published_at, '', 'guid-404'],
      published: false
    )
    processor = build_item_processor(
      content_fetcher: fetcher,
      item_parser: build_item_parser(
        link_url: link_url,
        guid: 'guid-404',
        title_text: 'Missing Article',
        published_at: published_at,
        content_html: ''
      ),
      duplicate_tracker: duplicate_tracker,
      post_writer: post_writer
    )

    result = processor.process(item, 'Source', source, stats)

    assert_equal :created, result
    assert_equal 1, stats[:not_found]
    assert_equal 1, stats[:created]
    duplicate_tracker.verify
    post_writer.verify
    fetcher.verify
  end

  def test_process_item_records_duplicates_after_canonical_update
    stats = Mayhem::News::RssImporter::FeedStats.new
    item = Object.new
    source = build_source_record
    link_url = 'https://example.com/article'
    normalized = Seldon::Support::UrlNormalizer.normalize(link_url, base: source&.website_url)
    updated_url = 'https://example.com/canonical'
    fetcher = Minitest::Mock.new
    fetcher.expect(:fetch, { html: '<p>body</p>', canonical_url: updated_url }, [link_url])
    duplicate_tracker = Minitest::Mock.new
    duplicate_tracker.expect(:duplicate?, false, [normalized, 'guid-dup'])
    duplicate_tracker.expect(:duplicate?, true, [updated_url, 'guid-dup'])
    processor = build_item_processor(
      content_fetcher: fetcher,
      item_parser: build_item_parser(
        link_url: link_url,
        guid: 'guid-dup',
        title_text: 'Title',
        published_at: Time.now,
        content_html: ''
      ),
      canonicalizer: build_canonicalizer,
      duplicate_tracker: duplicate_tracker,
      post_writer: Minitest::Mock.new
    )

    result = processor.process(item, 'Source', source, stats)

    assert_nil result
    assert_equal 1, stats[:duplicates]
    duplicate_tracker.verify
    fetcher.verify
  end

  def test_process_item_writes_post_and_registers_duplicate
    stats = Mayhem::News::RssImporter::FeedStats.new
    item = Object.new
    source = build_source_record
    link_url = 'https://example.com/article'
    normalized = Seldon::Support::UrlNormalizer.normalize(link_url, base: source&.website_url)
    published_at = Time.now
    duplicate_tracker = Minitest::Mock.new
    duplicate_tracker.expect(:duplicate?, false, [normalized, 'guid-123'])
    duplicate_tracker.expect(:register, nil, [normalized, 'guid-123'])
    post_writer = Minitest::Mock.new
    post_writer.expect(
      :write,
      :created,
      ['Source', 'Example Title', normalized, published_at, '<p>body</p>', 'guid-123'],
      published: nil
    )
    processor = build_item_processor(
      content_fetcher: Minitest::Mock.new,
      item_parser: build_item_parser(
        link_url: link_url,
        guid: 'guid-123',
        title_text: 'Example Title',
        published_at: published_at,
        content_html: '<p>body</p>'
      ),
      canonicalizer: build_canonicalizer,
      duplicate_tracker: duplicate_tracker,
      post_writer: post_writer
    )

    result = processor.process(item, 'Source', source, stats)

    assert_equal :created, result
    assert_equal 1, stats[:created]
    duplicate_tracker.verify
    post_writer.verify
  end

  def test_unchanged_post_detects_matching_checksum
    normalized_html = Mayhem::Content::HtmlNormalizer.normalize('<p>body</p>', base_url: 'https://source')
    checksum = Mayhem::Content::HtmlNormalizer.checksum(normalized_html)
    record = write_post({
      'title' => 'Test',
      'date' => Time.utc(2025, 11, 25).iso8601,
      'feed_content' => '<p>body</p>',
      'feed_content_checksum' => checksum,
      'source_url' => 'https://source',
      'published' => true
    }, '<p>body</p>')

    assert @post_writer.send(:unchanged_post?, record, normalized_html, checksum, 'https://source')
  end

  def test_unchanged_post_returns_false_without_record
    refute @post_writer.send(:unchanged_post?, nil, 'body', 'checksum', 'https://source')
  end

  def test_unchanged_post_compares_normalized_html_with_link_base_url
    html = '<img src="/path?utm_source=track">'
    normalized_html = Mayhem::Content::HtmlNormalizer.normalize(html, base_url: 'https://example.com')
    checksum = Mayhem::Content::HtmlNormalizer.checksum(normalized_html)
    record = write_post({
      'title' => 'Test',
      'date' => Time.utc(2025, 11, 25).iso8601,
      'feed_content' => html,
      'source_url' => ''
    })

    assert @post_writer.send(:unchanged_post?, record, normalized_html, checksum, 'https://example.com')
  end

  def test_unchanged_post_returns_false_without_existing_content
    record = Struct.new(:feed_content_checksum, :feed_content, :source_url, :path, :id)
                   .new('old-checksum', nil, 'https://example.com', 'post.md', 'post.md')

    refute @post_writer.send(:unchanged_post?, record, 'body', 'new-checksum', 'https://example.com')
  end

  def test_unchanged_post_returns_false_on_compare_error
    record = Struct.new(:feed_content_checksum, :feed_content, :source_url, :path, :id)
                   .new(nil, '<p>body</p>', 'https://example.com', 'post.md', 'post.md')

    Mayhem::Content::HtmlNormalizer.stub(:normalize, ->(*_args) { raise Encoding::CompatibilityError, 'incompatible encodings' }) do
      refute @post_writer.send(:unchanged_post?, record, '<p>body</p>', 'checksum', 'https://example.com')
    end

    assert @logger.debugs.last.include?('Failed to compare existing post')
  end

  def test_canonical_link_calls_http_for_redirect_hosts
    url = 'https://pubmed.ncbi.nlm.nih.gov/item'
    @fake_http.resolved_url = 'https://pubmed.ncbi.nlm.nih.gov/item?utm_source=ignore'
    result = @canonicalizer.canonical_link(url)
    expected = Seldon::Support::UrlNormalizer.normalize(@fake_http.resolved_url)
    assert_equal expected, result
  end

  def test_fetch_article_body_returns_normalized_payload
    fetcher = Minitest::Mock.new
    fetcher.expect(:fetch, { html: 'body', canonical_url: 'https://example.com/canonical' }, ['https://example.com'])
    processor = build_item_processor(content_fetcher: fetcher)
    result = processor.send(:fetch_article_body, 'https://example.com')
    assert_equal 'body', result[:html]
    assert_equal 'https://example.com/canonical', result[:canonical_url]
    fetcher.verify
  end

  def test_fetch_article_body_returns_empty_without_url
    processor = build_item_processor(content_fetcher: Minitest::Mock.new)
    result = processor.send(:fetch_article_body, nil)
    assert_equal '', result[:html]
    assert_nil result[:canonical_url]
  end

  def test_fetch_article_body_marks_not_found_and_logs_warning
    error = Seldon::Support::HttpClient::NotFoundError.new(
      url: 'https://example.com/missing',
      origin_url: 'https://example.com/missing',
      operation: 'content_fetch'
    )
    fetcher = Class.new do
      define_method(:fetch) do |_url|
        raise error
      end
    end.new
    processor = build_item_processor(content_fetcher: fetcher)
    result = processor.send(:fetch_article_body, 'https://example.com/missing')

    assert_equal '', result[:html]
    assert_equal 'https://example.com/missing', result[:canonical_url]
    assert_equal true, result[:not_found]
    assert_includes @logger.warns.last, 'Article URL returned 404'
  end

  def test_fetch_article_body_logs_warning_on_http_error
    error = Seldon::Support::HttpClient::HttpError.new(
      url: 'https://example.com/error',
      origin_url: 'https://example.com/error',
      operation: 'content_fetch',
      status: 500
    )
    fetcher = Class.new do
      define_method(:fetch) do |_url|
        raise error
      end
    end.new
    processor = build_item_processor(content_fetcher: fetcher)
    result = processor.send(:fetch_article_body, 'https://example.com/error')

    assert_equal '', result[:html]
    assert_nil result[:canonical_url]
    assert_includes @logger.warns.last, 'Failed to fetch article body'
  end

  def test_fetch_article_body_logs_error_on_unexpected_exception
    fetcher = Class.new do
      def fetch(_url)
        raise StandardError, 'boom'
      end
    end.new
    processor = build_item_processor(content_fetcher: fetcher)
    result = processor.send(:fetch_article_body, 'https://example.com/error')

    assert_equal '', result[:html]
    assert_nil result[:canonical_url]
    assert_includes @logger.errors.last, 'Unexpected error scraping'
  end

  private

  def build_item_processor(content_fetcher:, item_parser: @item_parser, canonicalizer: @canonicalizer,
                           duplicate_tracker: @duplicate_tracker, post_writer: @post_writer, max_item_age_days: 365)
    Mayhem::News::RssImporter::ItemProcessor.new(
      item_parser: item_parser,
      canonicalizer: canonicalizer,
      content_fetcher: content_fetcher,
      duplicate_tracker: duplicate_tracker,
      post_writer: post_writer,
      max_item_age_days: max_item_age_days
    )
  end

  def build_item_parser(link_url:, guid:, title_text:, published_at:, content_html:)
    Class.new do
      define_method(:link_url) { |_item| link_url }
      define_method(:guid) { |_item| guid }
      define_method(:title_text) { |_item| title_text }
      define_method(:published_at) { |_item| published_at }
      define_method(:content_html) { |_item| content_html }
    end.new
  end

  def build_canonicalizer
    Class.new do
      def canonical_link(link_url, html_canonical: nil)
        html_canonical || link_url
      end

      def redirect_host?(_url)
        false
      end
    end.new
  end

  def write_post(front_matter, body = '')
    data = {
      'title' => front_matter['title'] || 'Test',
      'date' => front_matter['date'] || Time.now.utc.iso8601,
      'feed_content' => front_matter['feed_content'] || ''
    }.merge(front_matter)
    Mayhem::Models::News.create!(data, body: body)
  end

  def write_org_record(front_matter)
    data = { 'title' => front_matter['title'] || 'Test Org' }.merge(front_matter)
    Mayhem::Models::Organization.create!(data, body: '')
  end

  def build_source_record(website_url: nil)
    @source_sequence = (@source_sequence || 0) + 1
    data = { 'title' => "Source #{@source_sequence}" }
    data['website_url'] = website_url if website_url
    Mayhem::Models::Organization.create!(data, body: '')
  end
end
