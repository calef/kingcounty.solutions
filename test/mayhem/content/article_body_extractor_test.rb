# frozen_string_literal: true

require 'seldon'
require_relative '../../test_helper'
require_relative '../../../lib/mayhem/content/article_body_extractor'

class ArticleBodyExtractorTest < Minitest::Test
  def test_text_from_html_strips_markup_and_script
    html = <<~HTML
      <html>
        <head><title>Test</title><script>alert('nope')</script></head>
        <body>
          <main>
            <article>
              <p>Hello <strong>world</strong></p>
              <footer>Footer text</footer>
            </article>
          </main>
        </body>
      </html>
    HTML

    result = Mayhem::Content::ArticleBodyExtractor.text_from_html(html)

    assert_equal 'Hello world', result
  end

  def test_text_from_html_handles_nil
    assert_nil Mayhem::Content::ArticleBodyExtractor.text_from_html(nil)
  end

  def test_normalized_html_truncates_when_needed
    original = 'a' * 100
    truncated = Mayhem::Content::ArticleBodyExtractor.normalized_html(original, max_chars: 10)

    assert_equal 'a' * 10, truncated
  end

  def test_normalized_html_returns_nil_for_nil
    assert_nil Mayhem::Content::ArticleBodyExtractor.normalized_html(nil)
  end

  def test_normalized_html_returns_full_when_within_limit
    sample = '<p>short</p>'

    assert_equal Seldon::Support::EncodingUtils.ensure_utf8(sample),
                 Mayhem::Content::ArticleBodyExtractor.normalized_html(sample, max_chars: 100)
  end
end
