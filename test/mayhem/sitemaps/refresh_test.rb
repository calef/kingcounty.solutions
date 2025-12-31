# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/sitemaps/refresh'

class SitemapsRefreshTest < Minitest::Test
  class FakeHttpClient
    def initialize(responses)
      @responses = responses
    end

    def fetch(url, accept:)
      @responses[url] || { body: '', content_type: 'text/plain', final_url: url }
    end
  end

  def setup
    @repo_override = FMRepo::TestHelpers.with_temp_repo(role: :websites)
    @xml_repo = FMRepo::TestHelpers.with_temp_repo(role: :xml_sitemaps)
    @sitemap_index_repo = FMRepo::TestHelpers.with_temp_repo(role: :sitemap_index)
    @url_set_repo = FMRepo::TestHelpers.with_temp_repo(role: :url_sets)
    @website = Mayhem::Models::Website.create!(
      {
        'title' => 'Example Site',
        'homepage_url' => 'https://example.com',
        'robots_txt_url' => 'https://example.com/robots.txt',
        'xml_sitemap_urls' => ['https://example.com/old.xml']
      },
      body: ''
    )
  end

  def teardown
    @repo_override&.cleanup
    @xml_repo&.cleanup
    @sitemap_index_repo&.cleanup
    @url_set_repo&.cleanup
  end

  def test_refresh_updates_website_and_creates_xml_sitemaps
    robots_body = <<~ROBOTS
      User-agent: *
      Sitemap: https://example.com/alpha.xml
      Sitemap: /beta.xml
    ROBOTS

    http_client = FakeHttpClient.new(
      'https://example.com/robots.txt' => {
        body: robots_body,
        content_type: 'text/plain',
        final_url: 'https://example.com/robots.txt'
      },
      'https://example.com/alpha.xml' => {
        body: '<urlset><url>alpha</url></urlset>',
        content_type: 'application/xml',
        final_url: 'https://example.com/alpha.xml'
      },
      'https://example.com/beta.xml' => {
        body: '<urlset><url>beta</url></urlset>',
        content_type: 'application/xml',
        final_url: 'https://example.com/beta.xml'
      }
    )

    finder = Mayhem::SitemapDiscovery::Finder.new(http_client: http_client)
    Mayhem::Sitemaps::Refresh.new(http_client: http_client, sitemap_finder: finder).run

    refreshed = Mayhem::Models::Website.find(@website.id)
    assert_equal ['https://example.com/alpha.xml', 'https://example.com/beta.xml'], refreshed.xml_sitemap_urls

    sets = Mayhem::Models::UrlSet.where(website_id: refreshed.id).to_a
    assert_equal 2, sets.size
    alpha = sets.find { |record| record['url'] == 'https://example.com/alpha.xml' }
    beta = sets.find { |record| record['url'] == 'https://example.com/beta.xml' }

    assert_equal refreshed.id, alpha['website_id']
    assert_equal '<urlset><url>alpha</url></urlset>', alpha.body.strip
    assert alpha['last_modified']

    assert_equal refreshed.id, beta['website_id']
    assert_equal '<urlset><url>beta</url></urlset>', beta.body.strip
    assert beta['last_modified']
  end

  def test_refresh_uses_sitemap_index_model
    robots_body = <<~ROBOTS
      User-agent: *
      Sitemap: https://example.com/index.xml
    ROBOTS

    index_body = '<sitemapindex><sitemap><loc>https://example.com/alpha.xml</loc></sitemap></sitemapindex>'

    http_client = FakeHttpClient.new(
      'https://example.com/robots.txt' => {
        body: robots_body,
        content_type: 'text/plain',
        final_url: 'https://example.com/robots.txt'
      },
      'https://example.com/index.xml' => {
        body: index_body,
        content_type: 'application/xml',
        final_url: 'https://example.com/index.xml'
      }
    )

    finder = Mayhem::SitemapDiscovery::Finder.new(http_client: http_client)
    Mayhem::Sitemaps::Refresh.new(http_client: http_client, sitemap_finder: finder).run

    indexes = Mayhem::Models::SitemapIndex.where(website_id: @website.id).to_a
    assert_equal 1, indexes.size
    assert_equal index_body, indexes.first.body.strip

    xmls = Mayhem::Models::XmlSitemap.where(website_id: @website.id).to_a
    assert_equal 0, xmls.size
  end

  def test_refresh_writes_url_set_model
    robots_body = <<~ROBOTS
      User-agent: *
      Sitemap: https://example.com/sitemap.xml
    ROBOTS

    urlset_body = '<urlset><url><loc>https://example.com/page</loc></url></urlset>'

    http_client = FakeHttpClient.new(
      'https://example.com/robots.txt' => {
        body: robots_body,
        content_type: 'text/plain',
        final_url: 'https://example.com/robots.txt'
      },
      'https://example.com/sitemap.xml' => {
        body: urlset_body,
        content_type: 'application/xml',
        final_url: 'https://example.com/sitemap.xml'
      }
    )

    finder = Mayhem::SitemapDiscovery::Finder.new(http_client: http_client)
    Mayhem::Sitemaps::Refresh.new(http_client: http_client, sitemap_finder: finder).run

    url_sets = Mayhem::Models::UrlSet.where(website_id: @website.id).to_a
    assert_equal 1, url_sets.size
    assert_equal urlset_body, url_sets.first.body.strip

    xmls = Mayhem::Models::XmlSitemap.where(website_id: @website.id).to_a
    assert_equal 0, xmls.size
  end
end
