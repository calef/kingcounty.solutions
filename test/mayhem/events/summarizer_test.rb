# frozen_string_literal: true

require 'minitest/autorun'
require 'nokogiri'
require 'seldon'
require 'time'
require_relative '../../test_helper'
require_relative '../../../lib/mayhem/events/summarizer'

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

    def trace(_message); end
  end

  class FakeChatClient
    def initialize(response: nil)
      @response = response
    end

    def chat(*)
      @response
    end
  end

  class FakeHttpClient
    attr_reader :requests

    def initialize(response:)
      @response = response
      @requests = []
    end

    def fetch(url, accept:)
      @requests << { url: url, accept: accept }
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

  class FakeLocationClassifier
    def initialize(location_titles:)
      @location_titles = location_titles
    end

    def classify(*)
      @location_titles
    end
  end

  def setup
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @event_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :events)
    @logger = FakeLogger.new
    Seldon::Logging.logger = @logger
  end

  def teardown
    Seldon::Logging.reset_logger
    @news_repo_override.cleanup if @news_repo_override
    @event_repo_override.cleanup if @event_repo_override
  end

  def write_event(slug, front_matter, body = '')
    event = Mayhem::Models::Event.create!(front_matter, body: body)
    event.id
  end

  def write_post(slug, front_matter)
    post = Mayhem::Models::News.create!(front_matter, body: '')
    post.id
  end

  def build_summarizer(client_response:, topics: [], location_titles: ['Seattle'], http_body: '<html><body><article>Story</article></body></html>')
    client = FakeChatClient.new(response: client_response)
    http = FakeHttpClient.new(response: { body: http_body, content_type: 'text/html' })
    topic_classifier = FakeTopicClassifier.new(topics: topics)
    location_classifier = FakeLocationClassifier.new(location_titles: location_titles)
    Mayhem::Events::EventSummarizer.new(
      client: client,
      model: 'test-model',
      http_client: http,
      topic_classifier: topic_classifier,
      location_classifier: location_classifier
    )
  end

  def test_run_updates_event_and_unlinks_posts_without_topic_titles
    event_id = write_event('event-one', {
                             'title' => 'Test Event',
                             'start_date' => '2025-01-01',
                             'location' => 'Town Hall',
                             'source_url' => 'https://example.com/event',
                             'generated_from_post' => true,
                             'feed_content' => '<article>Body text</article>',
                             'feed_content_checksum' => 'abc'
                           }, '')
    post_id = write_post('post-one', { 'event_ids' => [event_id] })

    summarizer = build_summarizer(
      client_response: { 'choices' => [{ 'message' => { 'content' => 'Refined summary.' } }] },
      topics: [],
      location_titles: []
    )

    stats = summarizer.run

    assert_equal 1, stats[:updated]
    assert_equal 1, stats[:missing_topics]
    assert_equal 1, stats[:missing_locations]
    assert_equal 1, stats[:events_unlinked]
    event = Mayhem::Models::Event.find(event_id)

    assert_equal 'Refined summary.', event.body.strip
    refute event.published
    assert_empty event.topic_titles
    assert_empty event.location_titles
    post = Mayhem::Models::News.find(post_id)

    assert_empty post.event_ids
  end

  def test_run_records_original_source_html_for_generated_event
    html = '<article><p>Keep it local</p></article>'
    event_id = write_event('event-source-html', {
                             'title' => 'Source HTML',
                             'start_date' => '2025-08-08',
                             'location' => 'City Hall',
                             'generated_from_post' => true,
                             'feed_content' => html
                           })

    summarizer = build_summarizer(
      client_response: { 'choices' => [{ 'message' => { 'content' => 'Summary text' } }] },
      topics: ['Neighborhood'],
      location_titles: ['Seattle']
    )

    stats = summarizer.run

    assert_equal 1, stats[:updated]
    event = Mayhem::Models::Event.find(event_id)
    expected_html = Mayhem::Content::ArticleBodyExtractor.normalized_html(
      html,
      max_chars: Mayhem::Summarizer::Base::MAX_ARTICLE_CHARS
    )
    assert_equal expected_html, event.original_source_html
    assert_equal 'Summary text', event.body.strip
  end

  def test_run_records_failed_summary_when_llm_empty
    write_event('event-two', {
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
    write_event('event-three', {
                  'title' => 'No Source',
                  'start_date' => '2025-03-03',
                  'location' => 'Park'
                }, 'Body text')

    summarizer = build_summarizer(client_response: {})

    stats = summarizer.run

    assert_equal 1, stats[:skipped_missing_source]
    assert_match(/no source_url/, @logger.warns.last)
  end

  def test_run_handles_generated_from_post_missing_body
    write_event('event-generated', {
                  'title' => 'Generated',
                  'start_date' => '2025-04-04',
                  'location' => 'Gym',
                  'generated_from_post' => true
                }, '')

    summarizer = build_summarizer(client_response: {}, topics: ['Health'])

    stats = summarizer.run

    assert_equal 1, stats[:skipped_missing_body]
    assert_match(/generated from post but has no body/, @logger.warns.last)
  end

  def test_run_backfills_location_titles_for_already_summarized_event
    event_id = write_event('event-backfill', {
                             'title' => 'Already Summarized',
                             'start_date' => '2025-05-05',
                             'location' => 'Community Center',
                             'summarized' => true
                           }, 'This event is already summarized.')

    summarizer = build_summarizer(
      client_response: {},
      topics: ['Community'],
      location_titles: %w[Seattle Bellevue]
    )

    stats = summarizer.run

    assert_equal 1, stats[:locations_backfilled]
    assert_equal 0, stats[:updated]
    event = Mayhem::Models::Event.find(event_id)

    assert_equal %w[Seattle Bellevue], event.location_titles
    assert event.published
  end

  def test_run_marks_unpublished_when_backfilled_location_titles_empty
    event_id = write_event('event-no-locations', {
                             'title' => 'Already Summarized No Locations',
                             'start_date' => '2025-06-06',
                             'location' => 'Virtual',
                             'summarized' => true,
                             'image_checksums' => ['https://example.com/event.jpg']
                           }, 'This event has no relevant locations.')

    summarizer = build_summarizer(
      client_response: {},
      topics: ['Technology'],
      location_titles: []
    )

    stats = summarizer.run

    assert_equal 1, stats[:locations_backfilled]
    event = Mayhem::Models::Event.find(event_id)

    assert_empty event.location_titles
    assert_empty event.image_checksums
    refute event.published
  end

  def test_run_skips_classification_when_topic_titles_and_location_titles_explicitly_empty
    write_event('event-already-classified', {
                  'title' => 'Already Classified',
                  'start_date' => '2025-07-07',
                  'location' => 'Hall',
                  'summarized' => true,
                  'classified' => true,
                  'topic_titles' => [],
                  'location_titles' => []
                }, 'Existing summary')

    topic_classifier = Object.new
    def topic_classifier.classify(*)
      raise 'should not be invoked when topic_titles already exist'
    end

    location_classifier = Object.new
    def location_classifier.classify(*)
      raise 'should not be invoked when location_titles already exist'
    end

    summarizer = Mayhem::Events::EventSummarizer.new(
      client: FakeChatClient.new(response: {}),
      http_client: FakeHttpClient.new(response: { body: '<html></html>', content_type: 'text/html' }),
      topic_classifier: topic_classifier,
      location_classifier: location_classifier,
      model: 'test-model'
    )

    stats = summarizer.run

    assert_equal 1, stats[:skipped_already_summarized]
  end

  def test_run_skips_locked_events
    event_id = write_event('event-locked', {
                             'title' => 'Locked Event',
                             'start_date' => '2025-08-08',
                             'location' => 'Town Hall',
                             'locked' => true,
                             'source_url' => 'https://example.com/event'
                           }, 'Original body')

    summarizer = build_summarizer(client_response: {}, topics: ['Health'])

    stats = summarizer.run

    assert_equal 1, stats[:skipped_locked]
    assert_equal 0, stats[:updated]
    assert_match(/locked is true/, @logger.debugs.last)
    event = Mayhem::Models::Event.find(event_id)
    assert_equal true, event.locked
    refute event.summarized
  end

  def test_prefer_fallback_body_prefers_only_when_scraped_empty
    summarizer = build_summarizer(client_response: {})

    assert summarizer.send(:prefer_fallback_body?, '', 'Fallback body')
    refute summarizer.send(:prefer_fallback_body?, 'Scraped content', 'Fallback body')
    refute summarizer.send(:prefer_fallback_body?, ' ', '')
  end

  def test_handle_unusable_content_marks_unpublished_and_unlinks_posts
    event_id = write_event('event-empty', {
                             'title' => 'Empty Event',
                             'start_date' => '2025-09-09',
                             'location' => 'Library',
                             'source_url' => 'https://example.com/event',
                             'generated_from_post' => true
                           }, 'Old summary')
    post_id = write_post('post-one', { 'event_ids' => [event_id] })
    event = Mayhem::Models::Event.find(event_id)
    stats = Hash.new(0)
    event_pruner = Minitest::Mock.new
    event_pruner.expect(:unpublish, nil) { |doc| doc.save! }

    summarizer = Mayhem::Events::EventSummarizer.new(
      client: FakeChatClient.new(response: {}),
      http_client: FakeHttpClient.new(response: { body: '<html></html>', content_type: 'text/html' }),
      topic_classifier: FakeTopicClassifier.new(topics: []),
      location_classifier: FakeLocationClassifier.new(location_titles: []),
      event_pruner: event_pruner,
      model: 'test-model'
    )

    summarizer.send(:handle_unusable_content, event, event_id, stats, generated_from_post: true)

    event_pruner.verify
    updated = Mayhem::Models::Event.find(event_id)
    assert_equal true, updated.summarized
    refute updated.published
    assert_equal [], updated.topic_titles
    assert_equal [], updated.location_titles
    assert_equal '', updated.body
    assert_equal 1, stats[:failed_summary]
    assert_equal 1, stats[:events_unlinked]
    post = Mayhem::Models::News.find(post_id)
    assert_empty post.event_ids
  end

  def test_generate_summary_with_empty_location
    event_id = write_event('event-no-location', {
                             'title' => 'Virtual Event',
                             'start_date' => '2025-10-10T19:00:00-07:00',
                             'location' => '',
                             'generated_from_post' => true,
                             'feed_content' => '<article>Join us for a virtual gathering to discuss community topics.</article>'
                           })

    summarizer = build_summarizer(
      client_response: { 'choices' => [{ 'message' => { 'content' => 'Join us for a virtual gathering on Oct. 10, 2025, starting at 7 p.m. to discuss community topics.' } }] },
      topics: ['Community'],
      location_titles: ['King County']
    )

    stats = summarizer.run

    assert_equal 1, stats[:updated]
    event = Mayhem::Models::Event.find(event_id)
    refute_match(/\[location\]/, event.body, 'Summary should not contain [location] placeholder')
    assert_equal 'Join us for a virtual gathering on Oct. 10, 2025, starting at 7 p.m. to discuss community topics.', event.body.strip
  end
end
