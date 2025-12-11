# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require 'nokogiri'
require 'time'
require_relative '../../../lib/mayhem/events/event_summarizer'

class EventSummarizerTest < Minitest::Test
  class FakeLogger
    attr_reader :infos, :warns, :errors, :debugs

    def initialize
      @infos = []
      @warns = []
      @errors = []
      @debugs = []
    end

    %i[info warn error debug].each do |level|
      define_method(level) do |message|
        instance_variable_get("@#{level}s") << message
      end
    end
  end

  class FakeChatClient
    def initialize(response: nil)
      @response = response
    end

    def chat(parameters:)
      @response
    end
  end

  class FakeHttpClient
    attr_reader :requests

    def initialize(response:)
      @response = response
      @requests = []
    end

    def fetch(url, accept:, max_bytes:)
      @requests << { url: url, accept: accept, max_bytes: max_bytes }
      @response
    end
  end

  class FakeTopicClassifier
    def initialize(topics:)
      @topics = topics
    end

    def classify(_text)
      @topics
    end
  end

  def setup
    @tmp_events = Dir.mktmpdir('events')
    @tmp_posts = Dir.mktmpdir('posts')
    @tmp_topics = Dir.mktmpdir('topics')
    @logger = FakeLogger.new
    @original_posts_dir = Mayhem::Events::EventSummarizer.const_get(:POSTS_DIR)
    Mayhem::Events::EventSummarizer.send(:remove_const, :POSTS_DIR)
    Mayhem::Events::EventSummarizer.const_set(:POSTS_DIR, @tmp_posts)
  end

  def teardown
    FileUtils.remove_entry(@tmp_events)
    FileUtils.remove_entry(@tmp_posts)
    FileUtils.remove_entry(@tmp_topics)
    Mayhem::Events::EventSummarizer.send(:remove_const, :POSTS_DIR)
    Mayhem::Events::EventSummarizer.const_set(:POSTS_DIR, @original_posts_dir)
  end

  def write_event(slug, front_matter, body = '')
    path = File.join(@tmp_events, "#{slug}.md")
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, body))
    path
  end

  def write_post(slug, front_matter)
    path = File.join(@tmp_posts, "#{slug}.md")
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def build_summarizer(client_response:, topics: [], http_body: '<html><body><article>Story</article></body></html>')
    client = FakeChatClient.new(response: client_response)
    http = FakeHttpClient.new(response: { body: http_body, content_type: 'text/html' })
    topic_classifier = FakeTopicClassifier.new(topics: topics)
    Mayhem::Events::EventSummarizer.new(
      events_dir: @tmp_events,
      topic_dir: @tmp_topics,
      client: client,
      http_client: http,
      topic_classifier: topic_classifier,
      logger: @logger,
      model: 'test-model'
    )
  end

  def test_run_updates_event_and_unlinks_posts_without_topics
    slug = 'event-one'
    write_event(slug, {
      'title' => 'Test Event',
      'start_date' => '2025-01-01',
      'location' => 'Town Hall',
      'source_url' => 'https://example.com/event',
      'generated_from_post' => true
    }, 'Body text')
    write_post('post-one', { 'events' => [slug] })

    summarizer = build_summarizer(
      client_response: { 'choices' => [{ 'message' => { 'content' => 'Refined summary.' } }] },
      topics: []
    )

    stats = summarizer.run

    assert_equal 1, stats[:updated]
    assert_equal 1, stats[:missing_topics]
    assert_equal 1, stats[:events_unlinked]
    document = Mayhem::FrontMatter::Document.load(File.join(@tmp_events, "#{slug}.md"), logger: @logger)
    assert_equal 'Refined summary.', document.body.strip
    assert_equal false, document.front_matter['published']
    post_doc = Mayhem::FrontMatter::Document.load(File.join(@tmp_posts, 'post-one.md'), logger: @logger)
    assert_empty Array(post_doc.front_matter['events'])
  end

  def test_run_records_failed_summary_when_llm_empty
    slug = 'event-two'
    write_event(slug, {
      'title' => 'Test Event',
      'start_date' => '2025-02-02',
      'location' => 'Library',
      'source_url' => 'https://example.com/event'
    }, 'Body text')

    summarizer = build_summarizer(
      client_response: { 'choices' => [{ 'message' => { 'content' => '   ' } }] },
      topics: ['Food']
    )

    stats = summarizer.run

    assert_equal 1, stats[:failed_summary]
    assert_match(/could not summarize event/, @logger.warns.last)
  end

  def test_run_skips_missing_source_when_not_generated_from_post
    slug = 'event-three'
    write_event(slug, {
      'title' => 'No Source',
      'start_date' => '2025-03-03',
      'location' => 'Park'
    }, 'Body text')

    summarizer = build_summarizer(client_response: {})

    stats = summarizer.run

    assert_equal 1, stats[:skipped_missing_source]
    assert_match(/could not summarize event/, @logger.warns.last)
  end

  def test_run_handles_generated_from_post_missing_body
    slug = 'event-generated'
    write_event(slug, {
      'title' => 'Generated',
      'start_date' => '2025-04-04',
      'location' => 'Gym',
      'generated_from_post' => true
    }, '')

    summarizer = build_summarizer(client_response: {}, topics: ['Health'])

    stats = summarizer.run

    assert_equal 1, stats[:skipped_missing_body]
    assert_match(/could not summarize event/, @logger.warns.last)
  end
end
