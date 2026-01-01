# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/sitemap_index'
require 'mayhem/models/website'

class SitemapIndexModelTest < Minitest::Test
  def setup
    @website_repo = FMRepo::TestHelpers.with_temp_repo(role: :websites)
    @sitemap_repo = FMRepo::TestHelpers.with_temp_repo(role: :sitemap_index)
  end

  def teardown
    @sitemap_repo&.cleanup
    @website_repo&.cleanup
  end

  def test_creates_and_reads_sitemap_index
    website = Mayhem::Models::Website.create!(
      { 'title' => 'Example site', 'homepage_url' => 'https://example.com' },
      body: ''
    )

    record = Mayhem::Models::SitemapIndex.create!(
      {
        'url' => 'https://example.com/sitemap_index.xml',
        'website_id' => website.id,
        'last_modified' => '2024-01-01T00:00:00Z'
      },
      body: '<sitemapindex></sitemapindex>'
    )

    assert_equal '_sitemap_indexes/example-com-sitemap-index-xml.md', record.id
    assert_equal 'https://example.com/sitemap_index.xml', record.url
    assert_equal '2024-01-01T00:00:00Z', record.last_modified
    assert_equal website.id, record.website_id
    assert_equal website.id, record.website.id
  end

  def test_url_defaults_to_array_when_missing
    record = Mayhem::Models::SitemapIndex.create!({}, body: '')

    assert_nil record.url
    assert_nil record.last_modified
    assert_nil record.website_id
  end
end
