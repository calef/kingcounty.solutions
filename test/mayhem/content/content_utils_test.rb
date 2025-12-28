# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/content/content_utils'

class MayhemContentUtilsTest < Minitest::Test
  def test_normalized_markdown_returns_empty_for_blank
    assert_equal '', Mayhem::Content::ContentUtils.normalized_markdown(nil)
    assert_equal '', Mayhem::Content::ContentUtils.normalized_markdown(" \n ")
  end

  def test_normalized_markdown_converts_html_to_markdown
    html = '<p>Hello</p>'

    assert_equal 'Hello', Mayhem::Content::ContentUtils.normalized_markdown(html)
  end

  def test_normalized_markdown_falls_back_when_markdown_contains_html
    html = '<p>Bold</p>'

    ReverseMarkdown.stub(:convert, '<b>Bold</b>') do
      assert_equal 'Bold', Mayhem::Content::ContentUtils.normalized_markdown(html)
    end
  end

  def test_normalized_markdown_rescues_conversion_errors
    html = '<p>Broken</p>'

    ReverseMarkdown.stub(:convert, ->(_source) { raise StandardError, 'boom' }) do
      assert_equal 'Broken', Mayhem::Content::ContentUtils.normalized_markdown(html)
    end
  end
end
