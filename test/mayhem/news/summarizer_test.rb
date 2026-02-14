# frozen_string_literal: true

require 'minitest/autorun'
require 'seldon'
require_relative '../../test_helper'
require_relative '../../../lib/mayhem/news/summarizer'

class PostSummarizerTest < Minitest::Test
  def setup
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @tmp_topics = Dir.mktmpdir('topics')
    @logger = Seldon::Logging.build_logger(env_var: 'LOG_LEVEL')
  end

  def teardown
    @news_repo_override.cleanup if @news_repo_override
    FileUtils.remove_entry(@tmp_topics)
  end

  def build_summarizer(**overrides)
    topic_classifier = overrides.delete(:topic_classifier) ||
                       Class.new do
                         def classify(*) = []
                       end.new
    location_classifier = overrides.delete(:location_classifier) ||
                          Class.new do
                            def classify(*) = []
                          end.new

    Mayhem::News::PostSummarizer.new(
      topic_classifier: topic_classifier,
      location_classifier: location_classifier,
      **overrides
    )
  end

  def write_post(filename, front_matter, body = '')
    post = Mayhem::Models::News.create!(front_matter, body: body)
    post.id
  end

  def write_topic(filename, title, summary = '')
    path = File.join(@tmp_topics, filename)
    content = "---\ntitle: #{title}\n---\n#{summary}"
    File.write(path, content)
    path
  end

  def test_fetch_article_text_handles_fetch_error
    write_post('2025-01-01-test.md', { 'source_url' => 'http://bad', 'summarized' => false, 'feed_content' => '<p>body</p>' }, 'body')
    http_stub = Object.new
    def http_stub.fetch(*) = { body: '', 'content-type' => 'text/plain', final_url: 'http://ok' }
    summarizer = build_summarizer(client: Object.new)
    def summarizer.fetch_html(_url)
      raise StandardError, 'boom'
    end

    stats = summarizer.run
    # since fetch_article_text raises, the run should record an error for that file
    assert_equal 1, stats[:errors]
  end

  def test_classify_topics_parses_json_and_filters
    write_post('2025-01-02-test.md', {
                'source_url' => 'http://ok',
                'summarized' => false,
                'feed_content' => '<article>body</article>'
              }, 'body')
    write_topic('t1.md', 'Alpha', 'match')
    write_topic('t2.md', 'Beta', '')

    client = Object.new
    def client.chat(*)
      { 'choices' => [{ 'message' => { 'content' => '["Alpha"]' } }] }
    end

    summarizer = build_summarizer(client: client)
    # stub generate_summary to skip OpenAI call
    def summarizer.generate_summary(*) = 'summary'

    stats = summarizer.run

    assert_equal 1, stats[:updated]
  end

  def test_generate_summary_handles_rate_limit_and_error
    write_post(
      '2025-01-03-test.md',
      {
        'source_url' => 'http://ok2',
        'summarized' => false,
        'feed_content' => '<article><p>Fallback</p></article>'
      },
      'x'
    )
    client = Object.new
    # define method on singleton client that will raise once then return
    client_singleton = class << client; self; end
    client_singleton.send(:define_method, :chat) do |*|
      @__calls ||= 0
      if @__calls.zero?
        @__calls += 1
        raise Faraday::TooManyRequestsError, 'rate'
      end
      { 'choices' => [{ 'message' => { 'content' => ' result ' } }] }
    end

    # Use a summarizer with a client object that will raise once then return
    http_stub = Object.new
    def http_stub.fetch(*) = { body: 'abc', 'content-type' => 'text/plain', final_url: 'http://ok' }
    summarizer = build_summarizer(client: client)
    def summarizer.fetch_html(_url) = '<article><p>Scraped</p></article>'

    stats = summarizer.run

    assert_equal 1, stats[:updated]
  end

  def test_run_stores_original_source_html_from_scraped_html
    html = '<article><p>Scraped news</p></article>'
    post_id = write_post('2025-01-06-source-html.md', {
                           'source_url' => 'http://ok-detail',
                           'summarized' => false,
                           'feed_content' => '<article><p>Fallback</p></article>'
                         }, 'body')

    http_stub = Object.new
    def http_stub.fetch(*)
      { body: '<article><p>Scraped news</p></article>', 'content-type' => 'text/html', final_url: 'http://ok-detail' }
    end

    client = Object.new
    def client.chat(*)
      { 'choices' => [{ 'message' => { 'content' => 'Fresh summary.' } }] }
    end

    summarizer = build_summarizer(client: client)
    def summarizer.fetch_html(_url) = '<article><p>Scraped news</p></article>'

    stats = summarizer.run

    assert_equal 1, stats[:updated]
    post = Mayhem::Models::News.find(post_id)
    expected_html = Mayhem::Content::ArticleBodyExtractor.normalized_html(
      html,
      max_chars: Mayhem::Summarizer::Base::MAX_ARTICLE_CHARS
    )
    assert_equal expected_html, post.original_source_html
    assert_equal 'Fresh summary.', post.body.strip
  end

  def test_backfills_location_titles_for_unpublished_summarized_post
    post_id = write_post('2025-01-04-test.md', {
                           'source_url' => 'http://ok3',
                           'summarized' => true,
                           'published' => false,
                           'topic_titles' => [],
                           'image_checksums' => ['https://example.com/image.jpg']
                         }, 'Summarized post without locations')

    # For unpublished posts, we should not call the classifier
    # It should just set location_titles to [] and clear image_checksums
    location_classifier = Object.new
    def location_classifier.classify(*)
      raise 'Should not be called for unpublished posts'
    end

    summarizer = build_summarizer(
      client: Object.new,
      location_classifier: location_classifier
    )

    stats = summarizer.run

    assert_equal 1, stats[:locations_backfilled]
    post = Mayhem::Models::News.find(post_id)

    assert_empty post.location_titles
    assert_empty post.image_checksums
  end

  def test_run_skips_classification_when_topic_titles_and_location_titles_explicitly_empty
    write_post('2025-01-05-test.md', {
                 'source_url' => 'http://ok',
                 'summarized' => true,
                 'classified' => true,
                 'topic_titles' => [],
                 'location_titles' => []
               }, 'body')

    topic_classifier = Object.new
    def topic_classifier.classify(*)
      raise 'should not be invoked when topic_titles already exist'
    end

    location_classifier = Object.new
    def location_classifier.classify(*)
      raise 'should not be invoked when location_titles already exist'
    end

    summarizer = build_summarizer(
      client: Object.new,
      topic_classifier: topic_classifier,
      location_classifier: location_classifier
    )

    stats = summarizer.run

    assert_equal 0, stats[:updated]
  end

  def test_unpublishes_when_summary_missing_even_with_topics_and_locations
    post_id = write_post('2025-01-07-test.md', {
                           'summarized' => true,
                           'topic_titles' => ['Health'],
                           'location_titles' => ['Seattle']
                         }, '')

    summarizer = build_summarizer(client: Object.new)

    stats = summarizer.run

    assert_equal 1, stats[:updated]
    post = Mayhem::Models::News.find(post_id)
    assert_equal false, post.published
  end
end
