# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require_relative '../../lib/mayhem/support/url_utils'
require_relative '../../lib/mayhem/logging'

class UrlUtilsTest < Minitest::Test
  def test_absolutize_and_parse_host
    base = 'https://example.com/path/'
    assert_equal 'https://example.com/foo', Mayhem::Support::UrlUtils.absolutize(base, '/foo')
    assert_equal 'example.com', Mayhem::Support::UrlUtils.parse_host(base)
  end

  def test_enforce_https_and_non_feed
    base = 'https://example.com'
    http = 'http://example.com/feed.xml'
    https = Mayhem::Support::UrlUtils.enforce_https(base, http)
    assert_equal 'https://example.com/feed.xml', https
    assert_equal true, Mayhem::Support::UrlUtils.non_feed_url?('https://example.com/file.pdf')
  end
end
