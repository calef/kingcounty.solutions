# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/content/html_normalizer'

class HtmlNormalizerTest < Minitest::Test
  def test_normalize_url_attribute_returns_canonicalized_url_and_respects_base
    value = '/page?utm_source=campaign&b=2&a=1#fragment'

    normalized = Mayhem::Content::HtmlNormalizer.normalize_url_attribute(value, 'https://Example.COM/base/')

    assert_equal 'https://example.com/page?a=1&b=2#fragment', normalized
  end

  def test_canonicalize_url_removes_tracking_and_sorts_query
    url = 'HTTPS://Example.COM/Path?utm_medium=social&b=2&a=1#g'

    canonical = Mayhem::Content::HtmlNormalizer.canonicalize_url(url)

    assert_equal 'https://example.com/Path?a=1&b=2#g', canonical
  end

  def test_canonicalize_url_returns_original_for_non_http
    mailto = 'mailto:foo@example.com'

    assert_equal mailto, Mayhem::Content::HtmlNormalizer.canonicalize_url(mailto)
  end

  def test_tracking_param_detects_prefixes_and_names
    assert_equal true, Mayhem::Content::HtmlNormalizer.tracking_param?('fbclid')
    assert_equal true, Mayhem::Content::HtmlNormalizer.tracking_param?('utm_campaign')
    assert_equal true, Mayhem::Content::HtmlNormalizer.tracking_param?('mc_param')
    assert_equal false, Mayhem::Content::HtmlNormalizer.tracking_param?('page')
  end
end
