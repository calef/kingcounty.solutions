# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require 'ostruct'
require 'tmpdir'
require_relative '../../../lib/mayhem/websites/generator'

class WebsitesGeneratorTest < Minitest::Test
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

  class FakeHttpClient
    def initialize(body)
      @body = body
    end

    def fetch(url, accept:)
      { body: @body, content_type: 'text/html', final_url: url }
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
    @website_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :websites)
    @website_dir = Mayhem::Models::Website.collection_dir
    @logger = FakeLogger.new
    Mayhem::Logging.logger = @logger
    @http_client = FakeHttpClient.new('<html><head><title>Example Site</title></head></html>')
    @feed_finder = FakeFeedFinder.new(OpenStruct.new(ical_url: 'https://example.com/events.ics'))
    @sitemap_finder = FakeSitemapFinder.new(['https://example.com/sitemap.xml'])
    @generator = Mayhem::Websites::Generator.new(
      http_client: @http_client,
      feed_finder: @feed_finder,
      sitemap_finder: @sitemap_finder
    )
  end

  def teardown
    Mayhem::Logging.reset_logger
    @website_repo_override.cleanup if @website_repo_override
  end

  def test_run_creates_website_file_with_discovery
    @generator.run('https://example.com')

    files = Dir.glob(File.join(@website_dir, '*.md'))
    assert_equal 1, files.size
    website = Mayhem::Models::Website.find(File.basename(files.first, '.md'))
    assert_equal 'Example Site', website['title']
    assert_equal 'https://example.com', website['homepage_url']
    assert_equal 'https://example.com/events.ics', website['events_ical_url']
    assert_equal 'https://example.com/robots.txt', website['robots_txt_url']
    assert_equal ['https://example.com/sitemap.xml'], website['xml_sitemap_urls']
  end

  def test_run_skips_existing_homepage
    Mayhem::Models::Website.create!(
      { 'title' => 'Existing Site', 'homepage_url' => 'https://example.com' },
      body: ''
    )

    @generator.run('https://example.com')

    assert_includes @logger.infos.last, 'already exists'
    assert_equal 1, Dir.glob(File.join(@website_dir, '*.md')).size
  end
end
