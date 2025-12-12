# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/summarizer/post_summarizer'

class PostSummarizerTest < Minitest::Test
  def setup
    @tmp_posts = Dir.mktmpdir('posts')
    @tmp_topics = Dir.mktmpdir('topics')
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
  end

  def teardown
    FileUtils.remove_entry(@tmp_posts)
    FileUtils.remove_entry(@tmp_topics)
  end

  def write_post(filename, front_matter, body = '')
    path = File.join(@tmp_posts, filename)
    content = Mayhem::FrontMatter::Document.build_markdown(front_matter, body)
    File.write(path, content)
    path
  end

  def write_topic(filename, title, summary = '')
    path = File.join(@tmp_topics, filename)
    content = Mayhem::FrontMatter::Document.build_markdown({ 'title' => title }, summary)
    File.write(path, content)
    path
  end

  def test_fetch_article_text_handles_fetch_error
    write_post('2025-01-01-test.md', { 'source_url' => 'http://bad', 'summarized' => false }, 'body')
    http_stub = Object.new
    def http_stub.fetch(*) = { body: '', 'content-type' => 'text/plain', final_url: 'http://ok' }
    summarizer = Mayhem::News::PostSummarizer.new(posts_dir: @tmp_posts, topic_dir: @tmp_topics,
                                                  http_client: http_stub, logger: @logger, client: Object.new)
    def summarizer.fetch_article_text(_url)
      raise StandardError, 'boom'
    end

    stats = summarizer.run
    # since fetch_article_text raises, the run should record an error for that file
    assert_equal 1, stats[:errors]
  end

  def test_classify_topics_parses_json_and_filters
    write_post('2025-01-02-test.md', { 'source_url' => 'http://ok', 'summarized' => false }, 'body')
    write_topic('t1.md', 'Alpha', 'match')
    write_topic('t2.md', 'Beta', '')

    client = Object.new
    def client.chat(*)
      { 'choices' => [{ 'message' => { 'content' => '["Alpha"]' } }] }
    end

    summarizer = Mayhem::News::PostSummarizer.new(posts_dir: @tmp_posts, topic_dir: @tmp_topics,
                                                  http_client: Object.new, logger: @logger, client: client)
    # stub generate_summary to skip OpenAI call
    def summarizer.generate_summary(*) = 'summary'

    stats = summarizer.run

    assert_equal 1, stats[:updated]
  end

  def test_generate_summary_handles_rate_limit_and_error
    write_post('2025-01-03-test.md', { 'source_url' => 'http://ok2', 'summarized' => false }, 'x')
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
    summarizer = Mayhem::News::PostSummarizer.new(posts_dir: @tmp_posts, topic_dir: @tmp_topics,
                                                  http_client: http_stub, logger: @logger, client: client)
    def summarizer.fetch_article_text(_url) = 'abc'

    stats = summarizer.run

    assert_equal 1, stats[:updated]
  end

  def test_backfills_locations_for_unpublished_summarized_post
    write_post('2025-01-04-test.md', {
                 'source_url' => 'http://ok3',
                 'summarized' => true,
                 'published' => false,
                 'topics' => [],
                 'images' => ['https://example.com/image.jpg']
               }, 'Summarized post without locations')

    # For unpublished posts, we should not call the classifier
    # It should just set locations to [] and clear images
    location_classifier = Object.new
    def location_classifier.classify(*)
      raise 'Should not be called for unpublished posts'
    end

    summarizer = Mayhem::News::PostSummarizer.new(
      posts_dir: @tmp_posts,
      topic_dir: @tmp_topics,
      http_client: Object.new,
      logger: @logger,
      client: Object.new,
      location_classifier: location_classifier
    )

    stats = summarizer.run

    assert_equal 1, stats[:locations_backfilled]
    document = Mayhem::FrontMatter::Document.load(File.join(@tmp_posts, '2025-01-04-test.md'), logger: @logger)

    assert_empty document.front_matter['locations']
    assert_empty document.front_matter['images']
  end

  def test_run_skips_classification_when_topics_and_locations_explicitly_empty
    write_post('2025-01-05-test.md', {
                 'source_url' => 'http://ok',
                 'summarized' => true,
                 'topics' => [],
                 'locations' => []
               }, 'body')

    topic_classifier = Object.new
    def topic_classifier.classify(*)
      raise 'should not be invoked when topics already exist'
    end

    location_classifier = Object.new
    def location_classifier.classify(*)
      raise 'should not be invoked when locations already exist'
    end

    summarizer = Mayhem::News::PostSummarizer.new(
      posts_dir: @tmp_posts,
      topic_dir: @tmp_topics,
      http_client: Object.new,
      logger: @logger,
      client: Object.new,
      topic_classifier: topic_classifier,
      location_classifier: location_classifier
    )

    stats = summarizer.run

    assert_equal 0, stats[:updated]
  end
end
