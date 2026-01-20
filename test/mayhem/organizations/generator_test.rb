# frozen_string_literal: true

require 'json'
require 'minitest/autorun'
require 'nokogiri'
require 'ostruct'
require 'seldon'
require 'tmpdir'
require_relative '../../test_helper'
require_relative '../../../lib/mayhem/organizations/generator'
require_relative '../../../lib/mayhem/models/organization'
require_relative '../../../lib/mayhem/models/topic'

class OrganizationsGeneratorTest < Minitest::Test
  class FakeLogger
    attr_reader :infos, :warns

    def initialize
      @infos = []
      @warns = []
    end

    def info(message)
      @infos << message
    end

    def warn(message)
      @warns << message
    end
  end

  class FakeFeedFinder
    attr_reader :find_calls, :result

    def initialize(result = nil)
      @result = result
      @find_calls = []
    end

    def find(url)
      @find_calls << url
      result
    end
  end

  class FakeSitemapFinder
    attr_reader :find_calls, :result

    def initialize(result = [])
      @result = result
      @find_calls = []
    end

    def find(url)
      @find_calls << url
      result
    end
  end

  def setup
    @org_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :organizations)
    @org_repo = Mayhem::Models::Organization.repo
    @org_dir = Mayhem::Models::Organization.collection_dir
    @topic_dir = Dir.mktmpdir('topics')
    @topic_repo = FMRepo::Repository.new(root: @topic_dir)
    @logger = FakeLogger.new
    @fake_client = Object.new
    @feed_finder = FakeFeedFinder.new(OpenStruct.new(rss_url: 'https://feed', ical_url: 'https://calendar'))
    @sitemap_finder = FakeSitemapFinder.new(['https://example.com/sitemap.xml'])
    Seldon::Logging.logger = @logger
    @generator = Mayhem::Organizations::Generator.new(
      topic_repo: @topic_repo,
      client: @fake_client,
      feed_finder: @feed_finder,
      sitemap_finder: @sitemap_finder
    )
  end

  def teardown
    Seldon::Logging.reset_logger
    @org_repo_override.cleanup if @org_repo_override
    FileUtils.remove_entry(@topic_dir)
  end

  def write_org(front_matter)
    org = Mayhem::Models::Organization.create!(front_matter, body: 'body')
    org.id
  end

  def create_topic(title)
    Mayhem::Models::Topic.create!({ 'title' => title }, body: 'body', repo: @topic_repo)
  end

  def test_normalize_and_canonicalize_urls
    assert_equal 'https://example.com', @generator.send(:normalize_url, 'https://EXAMPLE.com/')
    assert_equal 'https://example.com/path', @generator.send(:canonical_url, 'example.com/path')
  end

  def test_load_existing_websites_and_types
    write_org({ 'title' => 'Org One', 'website_url' => 'https://example.com', 'type' => 'Nonprofit' })
    write_org({ 'title' => 'Org Two', 'website_url' => 'https://example.com/', 'type' => 'Nonprofit' })

    sites = @generator.send(:load_existing_websites)
    types = @generator.send(:load_existing_types)

    assert_includes sites, 'https://example.com'
    assert_includes types, 'Nonprofit'
  end

  def test_build_prompt_includes_topics_and_types
    prompt = @generator.send(:build_prompt, 'https://example.com', [{ url: 'https://example.com', text: 'text' }], ['Health'], ['Type A'])
    assert_includes prompt, 'Allowed topic titles: Health'
    assert_includes prompt, 'Allowed organization types: Type A'
  end

  def test_parse_response_strips_code_fence
    response = <<~JSON
      ```json
      {"title": "Org"}
      ```
    JSON
    parsed = @generator.send(:parse_response, response)
    assert_equal 'Org', parsed['title']

    assert_nil @generator.send(:parse_response, 'not json')
  end

  def test_build_front_matter_filters_types
    types = ['Community Group']
    data = {
      'acronym' => 'ABC',
      'type' => 'community group',
      'topic_titles' => ['Food']
    }
    fm = @generator.send(:build_front_matter, data, types: types)
    assert_equal 'Community Group', fm['type']
    assert_equal ['Food'], fm['topic_titles']
  end

  def test_normalize_value_and_enforce_type
    assert_nil Seldon::Support::ValueNormalizer.normalize_value('   ')
    assert_equal 'value', Seldon::Support::ValueNormalizer.normalize_value(' value ')
    assert_nil @generator.send(:enforce_type, 'Unknown', ['Known'])
    assert_equal 'Known', @generator.send(:enforce_type, 'known', ['Known'])
  end

  def test_discover_feed_urls_logs_warning_on_exception
    failing = FakeFeedFinder.new
    failed_gen = Mayhem::Organizations::Generator.new(topic_repo: @topic_repo, feed_finder: failing)
    failing.define_singleton_method(:find) { raise StandardError, 'boom' }
    result = failed_gen.send(:discover_feed_urls, 'https://example.com')
    assert_nil result
    assert_match(/Feed discovery failed/, @logger.warns.last)
  end

  def test_load_topics_sort_titles
    create_topic('B')
    create_topic('A')

    topics = @generator.send(:load_topics)

    assert_equal ['A', 'B'], topics
  end

  class FakeChatClient
    def initialize(body)
      @body = body
    end

    def chat(parameters:)
      { 'choices' => [{ 'message' => { 'content' => @body } }] }
    end
  end

  def test_run_creates_organization_file_with_feed
    create_topic('Health')

    generator = Mayhem::Organizations::Generator.new(
      topic_repo: @topic_repo,
      feed_finder: @feed_finder,
      sitemap_finder: @sitemap_finder
    )
    stub_pages(generator)

    response_body = JSON.generate({
      'title' => 'Test Organization',
      'type' => 'Community-Based Organization',
      'topic_titles' => ['Health']
    })
    generator.instance_variable_set(:@client, FakeChatClient.new(response_body))

    generator.run('https://example.com')

    orgs = Mayhem::Models::Organization.all.to_a
    assert_equal 1, orgs.size
    org = orgs.first
    assert_equal 'https://feed', org['news_rss_url']
    assert_equal ['Health'], org['topic_titles']
    assert_equal 'https://calendar', org['events_ical_url']
    assert_equal ['https://example.com/sitemap.xml'], org['website_xml_sitemap_urls']
  end

  def test_run_records_multiple_sitemaps
    create_topic('Health')

    sitemap_finder = FakeSitemapFinder.new([
      'https://example.com/sitemap.xml',
      'https://example.com/sitemap-index.xml',
      'https://example.com/sitemap.xml'
    ])
    generator = Mayhem::Organizations::Generator.new(
      topic_repo: @topic_repo,
      feed_finder: @feed_finder,
      sitemap_finder: sitemap_finder
    )
    stub_pages(generator)

    response_body = JSON.generate({
      'title' => 'Test Organization',
      'type' => 'Community-Based Organization',
      'topic_titles' => ['Health']
    })
    generator.instance_variable_set(:@client, FakeChatClient.new(response_body))

    generator.run('https://example.com')

    orgs = Mayhem::Models::Organization.all.to_a
    assert_equal 1, orgs.size
    org = orgs.first
    assert_equal [
      'https://example.com/sitemap.xml',
      'https://example.com/sitemap-index.xml'
    ], org['website_xml_sitemap_urls']
  end

  def test_run_omits_sitemap_when_missing
    create_topic('Health')

    sitemap_finder = FakeSitemapFinder.new(nil)
    generator = Mayhem::Organizations::Generator.new(
      topic_repo: @topic_repo,
      feed_finder: @feed_finder,
      sitemap_finder: sitemap_finder
    )
    stub_pages(generator)

    response_body = JSON.generate({
      'title' => 'Test Organization',
      'type' => 'Community-Based Organization',
      'topic_titles' => ['Health']
    })
    generator.instance_variable_set(:@client, FakeChatClient.new(response_body))

    generator.run('https://example.com')

    orgs = Mayhem::Models::Organization.all.to_a
    assert_equal 1, orgs.size
    org = orgs.first
    assert_nil org['website_xml_sitemap_urls']
  end

  def test_run_skips_existing_website
    write_org({ 'title' => 'Existing', 'website_url' => 'https://example.com' })
    generator = Mayhem::Organizations::Generator.new(
      topic_repo: @topic_repo,
      feed_finder: @feed_finder,
      sitemap_finder: @sitemap_finder
    )
    stub_pages(generator)
    generator.instance_variable_set(:@client, FakeChatClient.new(JSON.generate('title' => 'X')))

    generator.run('https://example.com/')

    assert_includes @logger.infos.last, 'already exists'
    assert_equal 1, Mayhem::Models::Organization.all.to_a.size
  end

  def stub_pages(generator)
    generator.define_singleton_method(:gather_pages) do |url|
      [{ url: url, text: 'content', doc: Nokogiri::HTML('<html><body>content</body></html>') }]
    end
  end
end
