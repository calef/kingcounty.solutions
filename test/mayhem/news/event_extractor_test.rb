# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require 'time'
require_relative '../../test_helper'
require 'mayhem/news/event_extractor'
require 'mayhem/front_matter/document'
require 'mayhem/logging'

# TODO: change from using mayhem/front_matter/document to using the appropriate Mayhem::Models classes instead.

class EventExtractorTest < Minitest::Test
  def setup
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @tmpdir = Mayhem::Models::News.repo.root.to_s
    @posts_dir = Mayhem::Models::News.collection_dir
    @events_dir = File.join(@tmpdir, '_events')
    FileUtils.mkdir_p(@posts_dir)
    FileUtils.mkdir_p(@events_dir)
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')
  end

  def teardown
    @news_repo_override.cleanup if @news_repo_override
  end

  def test_skips_locked_posts
    write_post('2025-01-01-locked.md', locked: true)
    mock_chat_client = Minitest::Mock.new

    extractor = Mayhem::News::EventExtractor.new(
      events_dir: @events_dir,
      chat_client: mock_chat_client,
      logger: @logger
    )

    stats = extractor.run

    assert_equal 1, stats[:skipped_locked]
    assert_equal 0, stats[:posts_with_events]
    mock_chat_client.verify
  end

  def test_skips_unpublished_posts
    write_post('2025-01-01-unpublished.md', published: false)
    mock_chat_client = Minitest::Mock.new

    extractor = Mayhem::News::EventExtractor.new(
      events_dir: @events_dir,
      chat_client: mock_chat_client,
      logger: @logger
    )

    stats = extractor.run

    assert_equal 1, stats[:skipped_unpublished]
    assert_equal 0, stats[:posts_with_events]
    mock_chat_client.verify
  end

  def test_skips_already_extracted_posts
    write_post('2025-01-01-extracted.md', events_extracted: true)
    mock_chat_client = Minitest::Mock.new

    extractor = Mayhem::News::EventExtractor.new(
      events_dir: @events_dir,
      chat_client: mock_chat_client,
      logger: @logger
    )

    stats = extractor.run

    assert_equal 1, stats[:skipped_already_extracted]
    assert_equal 0, stats[:posts_with_events]
    mock_chat_client.verify
  end

  def test_skips_unsummarized_posts
    path = write_post('2025-01-01-unsummarized.md', summarized: false)
    mock_chat_client = Class.new do
      def call(*)
        raise 'Event extractor should not run on unsummarized posts'
      end
    end.new

    extractor = Mayhem::News::EventExtractor.new(
      events_dir: @events_dir,
      chat_client: mock_chat_client,
      logger: @logger
    )

    stats = extractor.run

    assert_equal 1, stats[:skipped_unsummarized]

    doc = Mayhem::FrontMatter::Document.load(path, logger: @logger)
    assert_nil doc.front_matter['events_extracted']
    assert_nil doc.front_matter['event_ids']
    assert Dir.glob(File.join(@events_dir, '*.md')).empty?
  end

  def test_marks_post_when_no_events_found
    write_post('2025-01-01-no-events.md', title: 'Just news')
    mock_chat_client = Minitest::Mock.new
    mock_chat_client.expect(:call, '[]') do |args|
      args.is_a?(Hash) && args.key?(:messages)
    end

    extractor = Mayhem::News::EventExtractor.new(
      events_dir: @events_dir,
      chat_client: mock_chat_client,
      logger: @logger
    )

    stats = extractor.run

    assert_equal 1, stats[:no_events_found]
    assert_equal 0, stats[:posts_with_events]

    # Verify post was marked as extracted
    post_path = File.join(@posts_dir, '2025-01-01-no-events.md')
    doc = Mayhem::FrontMatter::Document.load(post_path, logger: @logger)

    assert doc.front_matter['events_extracted']
    assert_empty doc.front_matter['event_ids']

    mock_chat_client.verify
  end

  def test_creates_events_and_updates_post
    write_post('2025-01-01-event-announcement.md',
               title: 'Upcoming Meeting',
               content: 'Join us for a meeting on Dec 15, 2025 at 6pm')

    event_json = [
      {
        'title' => 'Planning Meeting',
        'start_date' => '2025-12-15T18:00:00-08:00',
        'end_date' => nil,
        'location' => 'City Hall',
        'description' => 'Community planning meeting'
      }
    ].to_json

    mock_chat_client = Minitest::Mock.new
    mock_chat_client.expect(:call, event_json) do |args|
      args.is_a?(Hash) && args.key?(:messages)
    end

    extractor = Mayhem::News::EventExtractor.new(
      events_dir: @events_dir,
      chat_client: mock_chat_client,
      logger: @logger
    )

    stats = extractor.run

    assert_equal 1, stats[:posts_with_events]
    assert_equal 1, stats[:events_created]

    # Verify post was updated with event link
    post_path = File.join(@posts_dir, '2025-01-01-event-announcement.md')
    doc = Mayhem::FrontMatter::Document.load(post_path, logger: @logger)

    assert doc.front_matter['events_extracted']
    assert_equal 1, doc.front_matter['event_ids'].size

    # Verify event was created
    event_files = Dir.glob(File.join(@events_dir, '*.md'))

    assert_equal 1, event_files.size
    assert_equal File.basename(event_files.first), doc.front_matter['event_ids'].first

    event_doc = Mayhem::FrontMatter::Document.load(event_files.first, logger: @logger)

    assert_equal 'Planning Meeting', event_doc.front_matter['title']
    assert_equal '2025-12-15T18:00:00-08:00', event_doc.front_matter['start_date']
    assert_equal 'City Hall', event_doc.front_matter['location']
    assert_equal 'Test Source', event_doc.front_matter['organization_title']
    assert event_doc.front_matter['generated_from_post']

    mock_chat_client.verify
  end

  def test_skips_past_events
    write_post('2025-01-01-past-event.md',
               title: 'Past Event Announcement',
               content: 'Event happened last week')

    # LLM returns a past event
    event_json = [
      {
        'title' => 'Past Meeting',
        'start_date' => '2024-01-01T18:00:00-08:00',
        'end_date' => nil,
        'location' => 'Old Location',
        'description' => 'This already happened'
      }
    ].to_json

    mock_chat_client = Minitest::Mock.new
    mock_chat_client.expect(:call, event_json) do |args|
      args.is_a?(Hash) && args.key?(:messages)
    end

    extractor = Mayhem::News::EventExtractor.new(
      events_dir: @events_dir,
      chat_client: mock_chat_client,
      logger: @logger
    )

    stats = extractor.run

    # Post should be marked as extracted but no events created
    assert_equal 0, stats[:posts_with_events]
    assert_equal 0, stats[:events_created]
    assert_equal 1, stats[:past_events_skipped]

    # Verify post was marked as extracted with no events
    post_path = File.join(@posts_dir, '2025-01-01-past-event.md')
    doc = Mayhem::FrontMatter::Document.load(post_path, logger: @logger)

    assert doc.front_matter['events_extracted']
    assert_empty doc.front_matter['event_ids']

    # Verify no event files were created
    event_files = Dir.glob(File.join(@events_dir, '*.md'))

    assert_equal 0, event_files.size

    mock_chat_client.verify
  end

  private

  def write_post(filename, options = {})
    organization_title = options[:organization_title] || 'Test Source'
    front_matter = {
      'date' => options[:date] || '2025-01-01T12:00:00-08:00',
      'title' => options[:title] || 'Test Post',
      'organization_title' => organization_title,
      'source_url' => options[:source_url] || 'https://example.com/post'
    }
    front_matter['locked'] = true if options[:locked]
    front_matter['published'] = false if options[:published] == false
    front_matter['events_extracted'] = true if options[:events_extracted]
    front_matter['summarized'] = options.fetch(:summarized, true)

    body = options[:content] || 'Test content'

    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, body))
    path
  end
end
