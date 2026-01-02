# frozen_string_literal: true

require 'seldon'
require_relative '../../test_helper'
require_relative '../../../lib/mayhem/content/content_fetcher'

class ContentFetcherTest < Minitest::Test
  class StubHttpClient
    attr_reader :calls

    def initialize(body, final_url)
      @body = body
      @final_url = final_url
      @calls = []
    end

    def fetch(url, accept:)
      @calls << { url: url, accept: accept }
      {
        body: @body,
        final_url: @final_url
      }
    end
  end

  def setup
    @logger = Seldon::Logging.build_logger(env_var: 'LOG_LEVEL')
  end

  def test_returns_selector_snippet_and_canonical_url
    html = <<~HTML
      <html><body>
        <article class="article-body">
          <p>Paragraph   with   gaps</p>
          <script>console.log('noise')</script>
        </article>
        <nav>remove me</nav>
      </body></html>
    HTML

    client = StubHttpClient.new(html, 'https://example.com/clean')
    fetcher = Mayhem::Content::ContentFetcher.new(http_client: client)

    result = fetcher.fetch('https://example.com/page')

    assert_equal('https://example.com/clean', result[:canonical_url])
    assert_equal('<p>Paragraph with gaps</p>', result[:html])
    refute_includes result[:html], '<nav>'
    refute_includes result[:html], '<script>'
  end

  def test_falls_back_to_body_and_drops_empty_nodes
    html = <<~HTML
      <html><body>
        <article class="article-body"></article>
        <main>
          <div></div>
          <p>Body   text</p>
        </main>
      </body></html>
    HTML

    client = StubHttpClient.new(html, 'https://example.com/body')
    fetcher = Mayhem::Content::ContentFetcher.new(http_client: client)

    result = fetcher.fetch('https://example.com/body')

    assert_equal('<p>Body text</p>', result[:html])
  end
end
