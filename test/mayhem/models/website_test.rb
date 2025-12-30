# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/website'
require 'mayhem/models/organization'

class WebsiteModelTest < Minitest::Test
  def test_creates_and_reads_websites
    FMRepo::TestHelpers.with_temp_repo(role: :websites) do
      record = Mayhem::Models::Website.create!(
        {
          'title' => 'Example Site',
          'homepage_url' => 'https://example.org',
          'events_ical_url' => 'https://example.org/events.ics',
          'robots_txt_url' => 'https://example.org/robots.txt',
          'xml_sitemap_urls' => ['https://example.org/sitemap.xml']
        },
        body: ''
      )

      assert_equal '_websites/example-site.md', record.id
      assert_equal 'Example Site', record.title
      assert_equal 'https://example.org', record.homepage_url
      assert_equal 'https://example.org/events.ics', record.events_ical_url
      assert_equal 'https://example.org/robots.txt', record.robots_txt_url
      assert_equal ['https://example.org/sitemap.xml'], record.xml_sitemap_urls

      loaded = Mayhem::Models::Website.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Example Site', loaded.title
    end
  end

  def test_optional_fields_can_be_nil_or_empty
    FMRepo::TestHelpers.with_temp_repo(role: :websites) do
      record = Mayhem::Models::Website.create!(
        { 'title' => 'Minimal Site' },
        body: ''
      )

      assert_nil record.events_ical_url
      assert_nil record.homepage_url
      assert_nil record.robots_txt_url
      assert_equal [], record.xml_sitemap_urls
    end
  end

  def test_organization_lookup_by_homepage_url
    FMRepo::TestHelpers.with_temp_repo(role: :organizations) do
      organization = Mayhem::Models::Organization.create!(
        { 'title' => 'Example Org', 'type' => 'Agency', 'website_url' => 'https://example.org' },
        body: 'Org body.'
      )

      FMRepo::TestHelpers.with_temp_repo(role: :websites) do
        record = Mayhem::Models::Website.create!(
          { 'title' => 'Example Site', 'homepage_url' => 'https://example.org' },
          body: ''
        )

        assert_equal organization.id, record.organization.id
      end
    end
  end
end
