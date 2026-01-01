# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/websites/refresh'

class WebsitesRefreshTest < Minitest::Test
  class FakeFinder
    def initialize(results = {})
      @results = results
    end

    def find(url)
      @results.fetch(url, [])
    end
  end

  class FakeRobotsRefresher
    attr_reader :calls

    def initialize(result = 'https://example.com/robots.txt')
      @result = result
      @calls = []
    end

    def refresh(website)
      @calls << website
      @result
    end
  end

  class FakeSitemapsRefresher
    attr_reader :calls

    def initialize
      @calls = []
    end

    def refresh(website, urls)
      @calls << [website, urls]
    end
  end

  def setup
    @repo_override = FMRepo::TestHelpers.with_temp_repo(role: :websites)
    @website = Mayhem::Models::Website.create!(
      {
        'title' => 'Example Site',
        'homepage_url' => 'https://example.com'
      },
      body: ''
    )
  end

  def teardown
    @repo_override&.cleanup
  end

  def test_refresh_updates_sitemap_urls_and_delegates
    finder = FakeFinder.new('https://example.com' => ['https://example.com/alpha.xml'])
    robots = FakeRobotsRefresher.new('https://example.com/robots.txt')
    sitemaps = FakeSitemapsRefresher.new
    refresher = Mayhem::Websites::Refresh.new(
      sitemap_finder: finder,
      robots_refresher: robots,
      sitemaps_refresher: sitemaps
    )

    sitemap_urls = refresher.refresh(@website)

    refreshed = Mayhem::Models::Website.find(@website.id)
    assert_equal ['https://example.com/alpha.xml'], sitemap_urls
    assert_equal ['https://example.com/alpha.xml'], refreshed.xml_sitemap_urls

    assert_equal 1, sitemaps.calls.size
    assert_equal ['https://example.com/alpha.xml'], sitemaps.calls.first[1]
  end

  def test_refresh_prefers_gz_versions
    finder = FakeFinder.new(
      'https://example.com' => [
        'https://example.com/data.xml',
        'https://example.com/data.xml.gz'
      ]
    )
    refresher = Mayhem::Websites::Refresh.new(
      sitemap_finder: finder,
      robots_refresher: FakeRobotsRefresher.new,
      sitemaps_refresher: FakeSitemapsRefresher.new
    )

    sitemap_urls = refresher.refresh(@website)

    assert_equal ['https://example.com/data.xml.gz'], sitemap_urls
  end

  def test_refresh_skips_when_robots_missing
    finder = FakeFinder.new('https://example.com' => ['https://example.com/index.xml'])
    robots = FakeRobotsRefresher.new(nil)
    sitemaps = FakeSitemapsRefresher.new
    refresher = Mayhem::Websites::Refresh.new(
      sitemap_finder: finder,
      robots_refresher: robots,
      sitemaps_refresher: sitemaps
    )

    result = refresher.refresh(@website)

    assert_equal [], result
    assert_empty sitemaps.calls
  end

  def test_run_processes_all_websites
    second = Mayhem::Models::Website.create!(
      {
        'title' => 'Second Site',
        'homepage_url' => 'https://second.example'
      },
      body: ''
    )
    finder = FakeFinder.new(
      'https://example.com' => ['https://example.com/alpha.xml'],
      'https://second.example' => ['https://second.example/beta.xml']
    )
    robots = FakeRobotsRefresher.new('https://example.com/robots.txt')
    sitemaps = FakeSitemapsRefresher.new
    refresher = Mayhem::Websites::Refresh.new(
      sitemap_finder: finder,
      robots_refresher: robots,
      sitemaps_refresher: sitemaps
    )

    refresher.run

    assert_equal 2, sitemaps.calls.size
    assert_equal ['https://example.com/alpha.xml'], sitemaps.calls[0][1]
    assert_equal ['https://second.example/beta.xml'], sitemaps.calls[1][1]
  end
end
