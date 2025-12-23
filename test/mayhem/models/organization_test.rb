# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/organization'

class OrganizationModelTest < Minitest::Test
  def test_creates_and_reads_organizations
    FMRepo::TestHelpers.with_temp_repo(role: :organizations) do
      record = Mayhem::Models::Organization.create!(
        {
          'title' => 'Test Organization',
          'type' => 'Community-Based Organization',
          'website_url' => 'https://example.org',
          'phone' => '206-555-0123',
          'email' => 'contact@example.org',
          'address' => '123 Main St, Seattle, WA 98101',
          'topic_titles' => ['Housing', 'Food'],
          'parent_organization_title' => 'Parent Org'
        },
        body: 'Test organization description.'
      )

      assert_equal '_organizations/test-organization.md', record.id
      assert_equal 'Test Organization', record.title
      assert_equal 'Community-Based Organization', record.type
      assert_equal 'https://example.org', record.website_url
      assert_equal '206-555-0123', record.phone
      assert_equal 'contact@example.org', record.email
      assert_equal '123 Main St, Seattle, WA 98101', record.address
      assert_equal ['Housing', 'Food'], record.topic_titles
      assert_equal 'Parent Org', record.parent_organization_title
      assert_equal 'Test organization description.', record.body.strip

      loaded = Mayhem::Models::Organization.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Test Organization', loaded.title
    end
  end

  def test_parent_organization_returns_matching_organization
    FMRepo::TestHelpers.with_temp_repo(role: :organizations) do
      parent = Mayhem::Models::Organization.create!(
        { 'title' => 'Parent Org', 'type' => 'Agency' },
        body: 'The parent organization.'
      )
      child = Mayhem::Models::Organization.create!(
        { 'title' => 'Child Org', 'type' => 'Program', 'parent_organization_title' => 'Parent Org' },
        body: 'A child organization.'
      )

      assert_equal parent.id, child.parent_organization.id
      assert_equal 'Parent Org', child.parent_organization.title
      assert child.parent_organization?
    end
  end

  def test_parent_organization_handles_missing_parent
    FMRepo::TestHelpers.with_temp_repo(role: :organizations) do
      child = Mayhem::Models::Organization.create!(
        { 'title' => 'Solo Org', 'type' => 'Agency', 'parent_organization_title' => 'Missing Org' },
        body: 'A solo organization.'
      )

      assert_nil child.parent_organization
      refute child.parent_organization?
    end
  end

  def test_parent_organization_handles_blank_parent_title
    FMRepo::TestHelpers.with_temp_repo(role: :organizations) do
      child = Mayhem::Models::Organization.create!(
        { 'title' => 'Solo Org', 'type' => 'Agency' },
        body: 'A solo organization.'
      )

      assert_nil child.parent_organization
      refute child.parent_organization?
    end
  end

  def test_optional_fields_can_be_nil_or_empty
    FMRepo::TestHelpers.with_temp_repo(role: :organizations) do
      record = Mayhem::Models::Organization.create!(
        { 'title' => 'Minimal Org', 'type' => 'Agency' },
        body: 'Minimal organization.'
      )

      assert_nil record.acronym
      assert_nil record.address
      assert_nil record.email
      assert_nil record.events_ical_url
      assert_nil record.news_rss_url
      assert_nil record.phone
      assert_equal [], record.topic_titles
      assert_nil record.parent_organization_title
      assert_nil record.website_url
      assert_equal [], record.website_xml_sitemap_urls
    end
  end

  def test_acronym_field
    FMRepo::TestHelpers.with_temp_repo(role: :organizations) do
      record = Mayhem::Models::Organization.create!(
        { 'title' => 'YMCA Organization', 'type' => 'Agency', 'acronym' => 'YMCA' },
        body: 'Organization with acronym.'
      )

      assert_equal 'YMCA', record.acronym
    end
  end

  def test_events_ical_url_and_news_rss_url_fields
    FMRepo::TestHelpers.with_temp_repo(role: :organizations) do
      record = Mayhem::Models::Organization.create!(
        {
          'title' => 'News Org',
          'type' => 'Agency',
          'news_rss_url' => 'https://example.org/feed.rss',
          'events_ical_url' => 'https://example.org/events.ical'
        },
        body: 'Organization with feeds.'
      )

      assert_equal 'https://example.org/feed.rss', record.news_rss_url
      assert_equal 'https://example.org/events.ical', record.events_ical_url
    end
  end

  def test_website_xml_sitemap_urls_field
    FMRepo::TestHelpers.with_temp_repo(role: :organizations) do
      record = Mayhem::Models::Organization.create!(
        {
          'title' => 'Sitemap Org',
          'type' => 'Agency',
          'website_xml_sitemap_urls' => ['https://example.org/sitemap.xml']
        },
        body: 'Organization with sitemap.'
      )

      assert_equal ['https://example.org/sitemap.xml'], record.website_xml_sitemap_urls
    end
  end
end
