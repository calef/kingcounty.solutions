# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require_relative '../../lib/mayhem/support/url_normalizer'

class UrlNormalizerTest < Minitest::Test
  def test_absolute_and_protocol_relative
    assert_equal 'https://example.com/foo', Mayhem::Support::UrlNormalizer.normalize('https://example.com/foo')
    assert_equal 'https://example.com/foo', Mayhem::Support::UrlNormalizer.normalize('//example.com/foo')
  end

  def test_missing_host_with_base
    base = 'https://example.com/blog/'

    assert_equal 'https://example.com/posts/1', Mayhem::Support::UrlNormalizer.normalize('/posts/1', base: base)
    assert_equal 'https://example.com/blog/posts/1', Mayhem::Support::UrlNormalizer.normalize('posts/1', base: base)
  end

  def test_invalid_urls_return_nil
    assert_nil Mayhem::Support::UrlNormalizer.normalize('javascript:alert(1)')
    assert_nil Mayhem::Support::UrlNormalizer.normalize('not a url')
  end
end
