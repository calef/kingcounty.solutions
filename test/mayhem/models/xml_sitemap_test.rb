# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/xml_sitemap'
require 'mayhem/models/website'

class XmlSitemapModelTest < Minitest::Test
  def setup
    @repo = FMRepo::TestHelpers.with_temp_repo(role: :websites)
  end

  def teardown
    @repo&.cleanup
  end

  def test_creates_and_reads_xml_sitemap
    website = Mayhem::Models::Website.create!(
      { 'title' => 'Example site', 'homepage_url' => 'https://example.com' },
      body: ''
    )

    record = Mayhem::Models::XmlSitemap.create!(
      {
        'url' => 'https://example.com/sitemap.xml',
        'website_id' => website.id,
        'last_modified' => '2024-01-01T00:00:00Z'
      },
      body: '<urlset></urlset>'
    )

    assert_equal '_xml_sitemaps/https-example-com-sitemap-xml.md', record.id
    assert_equal 'https://example.com/sitemap.xml', record.url
    assert_equal '2024-01-01T00:00:00Z', record.last_modified
    assert_equal website.id, record.website_id
    assert_equal website.id, record.website.id
  end

  def test_url_defaults_to_nil_when_missing
    record = Mayhem::Models::XmlSitemap.create!({}, body: '')

    assert_nil record.url
    assert_nil record.last_modified
    assert_nil record.website_id
  end
end
