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
    @tmp_events = Mayhem::Models::Event.collection_dir
    @tmp_posts = Mayhem::Models::News.collection_dir
    @tmp_topics = Dir.mktmpdir('topics')
    @tmp_images = Dir.mktmpdir('images')
    @tmp_assets_root = Dir.mktmpdir('assets')
    @tmp_assets = File.join(@tmp_assets_root, 'images')
    FileUtils.mkdir_p(@tmp_assets)
    @logger = FakeLogger.new
    FileUtils.mkdir_p(@tmp_posts)
    FileUtils.mkdir_p(@tmp_events)
    Seldon::Logging.logger = @logger
  end

  def teardown
    Seldon::Logging.reset_logger
    FileUtils.remove_entry(@tmp_topics)
    FileUtils.remove_entry(@tmp_images)
    FileUtils.remove_entry(@tmp_assets_root)
    @news_repo_override.cleanup if @news_repo_override
    @event_repo_override.cleanup if @event_repo_override
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

  def event_id_for(slug)
    File.join('_events', "#{slug}.md")
  end

  def build_summarizer(client_response:, topics: [], location_titles: ['Seattle'], http_body: '<html><body><article>Story</article></body></html>')
    client = FakeChatClient.new(response: client_response)
    http = FakeHttpClient.new(response: { body: http_body, content_type: 'text/html' })
    topic_classifier = FakeTopicClassifier.new(topics: topics)
    location_classifier = FakeLocationClassifier.new(location_titles: location_titles)
    Mayhem::Events::EventSummarizer.new(
      assets_dir: @tmp_assets,
      client: client,
      model: 'test-model',
      http_client: http,
      topic_classifier: topic_classifier,
      location_classifier: location_classifier
    )
  end

  def test_run_updates_event_and_unlinks_posts_without_topic_titles
    slug = 'event-one'
    write_event(slug, {
                  'title' => 'Test Event',
                  'start_date' => '2025-01-01',
                  'location' => 'Town Hall',
                  'source_url' => 'https://example.com/event',
                  'generated_from_post' => true,
                  'feed_content' => '<article>Body text</article>',
                  'feed_content_checksum' => 'abc'
                }, '')
    write_post('post-one', { 'event_ids' => [event_id_for(slug)] })

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
    document = Mayhem::FrontMatter::Document.load(File.join(@tmp_events, "#{slug}.md"))

    assert_equal 'Refined summary.', document.body.strip
    refute document.front_matter['published']
    assert_empty Array(document.front_matter['topic_titles'])
    assert_empty Array(document.front_matter['location_titles'])
    post_doc = Mayhem::FrontMatter::Document.load(File.join(@tmp_posts, 'post-one.md'))

    assert_empty Array(post_doc.front_matter['event_ids'])
  end

  def test_run_records_original_source_html_for_generated_event
    slug = 'event-source-html'
    html = '<article><p>Keep it local</p></article>'
    write_event(slug, {
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
    document = Mayhem::FrontMatter::Document.load(File.join(@tmp_events, "#{slug}.md"))
    expected_html = Mayhem::Content::ArticleBodyExtractor.sanitized_html(
      html,
      max_chars: Mayhem::Events::EventSummarizer::MAX_ARTICLE_CHARS
    )
    assert_equal expected_html, document.front_matter['original_source_html']
    assert_equal 'Summary text', document.body.strip
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
    assert_match(/no source_url/, @logger.warns.last)
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
    assert_match(/generated from post but has no body/, @logger.warns.last)
  end

  def test_run_backfills_location_titles_for_already_summarized_event
    slug = 'event-backfill'
    write_event(slug, {
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
    document = Mayhem::FrontMatter::Document.load(File.join(@tmp_events, "#{slug}.md"))

    assert_equal %w[Seattle Bellevue], document.front_matter['location_titles']
    assert_nil document.front_matter['published']
  end

  def test_run_marks_unpublished_when_backfilled_location_titles_empty
    slug = 'event-no-locations'
    write_event(slug, {
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
    document = Mayhem::FrontMatter::Document.load(File.join(@tmp_events, "#{slug}.md"))

    assert_empty document.front_matter['location_titles']
    assert_empty document.front_matter['image_checksums']
    refute document.front_matter['published']
  end

  def test_run_skips_classification_when_topic_titles_and_location_titles_explicitly_empty
    slug = 'event-already-classified'
    write_event(slug, {
                  'title' => 'Already Classified',
                  'start_date' => '2025-07-07',
                  'location' => 'Hall',
                  'summarized' => true,
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
      assets_dir: @tmp_assets,
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
    slug = 'event-locked'
    path = write_event(slug, {
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
    document = Mayhem::FrontMatter::Document.load(path)
    assert_equal true, document.front_matter['locked']
    refute document.front_matter['summarized']
  end

  def test_prefer_fallback_body_prefers_only_when_scraped_empty
    summarizer = build_summarizer(client_response: {})

    assert summarizer.send(:prefer_fallback_body?, '', 'Fallback body')
    refute summarizer.send(:prefer_fallback_body?, 'Scraped content', 'Fallback body')
    refute summarizer.send(:prefer_fallback_body?, ' ', '')
  end

  def test_handle_unusable_content_marks_unpublished_and_unlinks_posts
    slug = 'event-empty'
    write_event(slug, {
                  'title' => 'Empty Event',
                  'start_date' => '2025-09-09',
                  'location' => 'Library',
                  'source_url' => 'https://example.com/event',
                  'generated_from_post' => true
                }, 'Old summary')
    write_post('post-one', { 'event_ids' => [event_id_for(slug)] })
    event_id = event_id_for(slug)
    event = Mayhem::Models::Event.find(event_id)
    stats = Hash.new(0)
    event_pruner = Minitest::Mock.new
    event_pruner.expect(:unpublish, nil, [event])

    summarizer = Mayhem::Events::EventSummarizer.new(
      assets_dir: @tmp_assets,
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
    assert_equal true, updated['summarized']
    refute updated['published']
    assert_equal [], Array(updated['topic_titles'])
    assert_equal [], Array(updated['location_titles'])
    assert_equal '', updated.body
    assert_equal 1, stats[:failed_summary]
    assert_equal 1, stats[:events_unlinked]
    post_doc = Mayhem::FrontMatter::Document.load(File.join(@tmp_posts, 'post-one.md'))
    assert_empty Array(post_doc.front_matter['event_ids'])
  end

  def test_generate_summary_with_empty_location
    slug = 'event-no-location'
    write_event(slug, {
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
    document = Mayhem::FrontMatter::Document.load(File.join(@tmp_events, "#{slug}.md"))
    refute_match(/\[location\]/, document.body, 'Summary should not contain [location] placeholder')
    assert_equal 'Join us for a virtual gathering on Oct. 10, 2025, starting at 7 p.m. to discuss community topics.', document.body.strip
  end
end
