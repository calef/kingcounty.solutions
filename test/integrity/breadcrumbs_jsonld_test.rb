# frozen_string_literal: true

require_relative '../test_helper'
require 'pathname'
require 'nokogiri'
require 'nokogiri/html5'
require 'json'
require_relative '../support/site_build_helper'

class BreadcrumbsJsonldTest < Minitest::Test
  def setup
    SiteBuildHelper.ensure_site_built
  end

  def test_organization_page_has_breadcrumb_jsonld
    path = File.join(SiteBuildHelper.destination, 'organizations', 'king-county', 'index.html')
    document = Nokogiri::HTML5.parse(File.read(path))

    breadcrumb_schema = find_breadcrumb_schema(document)
    refute_nil breadcrumb_schema, 'Expected to find BreadcrumbList JSON-LD schema'

    assert_equal 'https://schema.org', breadcrumb_schema['@context']
    assert_equal 'BreadcrumbList', breadcrumb_schema['@type']
    assert breadcrumb_schema['itemListElement'].is_a?(Array)
    assert breadcrumb_schema['itemListElement'].length >= 3, 'Expected at least Home, Organizations, and current page'

    # Verify structure of items
    breadcrumb_schema['itemListElement'].each_with_index do |item, index|
      assert_equal 'ListItem', item['@type']
      assert_equal index + 1, item['position']
      assert item['name'].is_a?(String), 'Expected name to be a string'

      # Last item should not have an 'item' URL
      if index < breadcrumb_schema['itemListElement'].length - 1
        assert item['item'].is_a?(String), "Expected item #{index + 1} to have an 'item' URL"
      end
    end
  end

  def test_topic_page_has_breadcrumb_jsonld
    path = File.join(SiteBuildHelper.destination, 'topics', 'shelter-and-housing', 'index.html')
    document = Nokogiri::HTML5.parse(File.read(path))

    breadcrumb_schema = find_breadcrumb_schema(document)
    refute_nil breadcrumb_schema, 'Expected to find BreadcrumbList JSON-LD schema'

    items = breadcrumb_schema['itemListElement']
    assert_equal 3, items.length

    # Verify structure
    assert_equal 'Home', items[0]['name']
    assert_equal 'Topics', items[1]['name']
    assert_equal 'Shelter & Housing', items[2]['name']
  end

  def test_organization_with_parent_has_breadcrumb_jsonld
    path = File.join(SiteBuildHelper.destination, 'organizations', 'best-starts-for-kids', 'index.html')
    document = Nokogiri::HTML5.parse(File.read(path))

    breadcrumb_schema = find_breadcrumb_schema(document)
    refute_nil breadcrumb_schema, 'Expected to find BreadcrumbList JSON-LD schema'

    items = breadcrumb_schema['itemListElement']
    assert items.length >= 4, 'Expected hierarchical breadcrumb trail for organization with parents'

    # Verify Home and Organizations are present
    assert_equal 'Home', items.first['name']
    assert_equal 'Organizations', items[1]['name']
  end

  private

  def find_breadcrumb_schema(document)
    scripts = document.css('script[type="application/ld+json"]')
    scripts.each do |script|
      begin
        data = JSON.parse(script.content)
        return data if data['@type'] == 'BreadcrumbList'
      rescue JSON::ParserError
        # Skip invalid JSON
      end
    end
    nil
  end
end
