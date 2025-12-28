# frozen_string_literal: true

require 'fileutils'
require_relative '../../test_helper'
require 'mayhem/content/source_url_checker'
require 'mayhem/front_matter/document'
require 'mayhem/logging'
require 'mayhem/models/event'
require 'mayhem/models/image'
require 'mayhem/models/news'

# TODO: change from using mayhem/front_matter/document to using the appropriate Mayhem::Models classes instead.

class SourceUrlCheckerTest < Minitest::Test
  def setup
    @news_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :news)
    @events_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :events)
    @images_repo_override = FMRepo::TestHelpers.with_temp_repo(role: :images)

    @news_repo = Mayhem::Models::News.repo
    @events_repo = Mayhem::Models::Event.repo
    @images_repo = Mayhem::Models::Image.repo

    @posts_dir = @news_repo.root.join('_posts').to_s
    @events_dir = @events_repo.root.join('_events').to_s
    @images_dir = @images_repo.root.join('_images').to_s
    @assets_dir = @images_repo.root.join('assets', 'images').to_s
    FileUtils.mkdir_p(@posts_dir)
    FileUtils.mkdir_p(@events_dir)
    FileUtils.mkdir_p(@images_dir)
    FileUtils.mkdir_p(@assets_dir)
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL', default_level: 'FATAL')
  end

  def teardown
    @news_repo_override.cleanup if @news_repo_override
    @events_repo_override.cleanup if @events_repo_override
    @images_repo_override.cleanup if @images_repo_override
  end

  def test_successful_url_check_does_not_modify_post
    post_path = write_post('2025-01-01-test.md', 'https://example.com/article')
    original_content = File.read(post_path)

    checker = build_checker(http_client: ->(_url) { :success })
    checker.run

    assert_equal original_content, File.read(post_path), 'Post should not be modified'
  end

  def test_not_found_url_unpublishes_post
    post_path = write_post('2025-01-01-test.md', 'https://example.com/missing')

    checker = build_checker(http_client: ->(_url) { :not_found })
    checker.run

    document = Mayhem::FrontMatter::Document.load(post_path)

    refute document.front_matter['published'], 'Post should be unpublished'
  end

  def test_not_found_url_clears_post_images
    image_id = 'image123'
    write_image_metadata(image_id)
    write_asset(image_id)
    post_path = write_post_with_image_checksums('2025-01-01-test.md', 'https://example.com/missing', [image_id])

    checker = build_checker(http_client: ->(_url) { :not_found })
    checker.run

    document = Mayhem::FrontMatter::Document.load(post_path)

    assert_empty document.front_matter['image_checksums'], 'Image IDs array should be cleared'
  end

  def test_not_found_url_removes_unreferenced_images
    unique_image = 'unique456'
    write_image_metadata(unique_image)
    write_asset(unique_image)
    write_post_with_image_checksums('2025-01-01-test.md', 'https://example.com/missing', [unique_image])

    checker = build_checker(http_client: ->(_url) { :not_found })
    checker.run

    refute_path_exists File.join(@images_dir, "#{unique_image}.md"), 'Image metadata should be removed'
    assert_empty Dir.glob(File.join(@assets_dir, "#{unique_image}.*")), 'Image assets should be removed'
  end

  def test_not_found_url_preserves_shared_images
    shared_image = 'shared789'
    write_image_metadata(shared_image)
    write_asset(shared_image)
    write_post_with_image_checksums('2025-01-01-test.md', 'https://example.com/missing', [shared_image])
    write_post_with_image_checksums('2025-01-02-other.md', 'https://example.com/valid', [shared_image])

    checker = build_checker(http_client: lambda { |url|
      url.include?('missing') ? :not_found : :success
    })
    checker.run

    assert_path_exists File.join(@images_dir, "#{shared_image}.md"), 'Shared image metadata should remain'
  end

  def test_error_status_logs_warning_but_does_not_modify_post
    post_path = write_post('2025-01-01-test.md', 'https://example.com/error')
    original_content = File.read(post_path)

    checker = build_checker(http_client: ->(_url) { :error })
    checker.run

    assert_equal original_content, File.read(post_path), 'Post should not be modified on error'
  end

  def test_not_found_event_is_deleted
    event_path = write_event('event123', 'https://example.com/missing-event')

    checker = build_checker(http_client: ->(_url) { :not_found })
    checker.run

    refute_path_exists event_path, 'Event should be deleted'
  end

  def test_successful_event_check_does_not_delete_event
    event_path = write_event('event456', 'https://example.com/valid-event')

    checker = build_checker(http_client: ->(_url) { :success })
    checker.run

    assert_path_exists event_path, 'Event should not be deleted'
  end

  def test_deleted_event_removed_from_post_references
    event_id = 'event789'
    event_filename = "#{event_id}.md"
    write_event(event_id, 'https://example.com/missing-event')
    post_path = write_post_with_event_ids('2025-01-01-test.md', 'https://example.com/valid', [event_filename])

    checker = build_checker(http_client: lambda { |url|
      url.include?('missing-event') ? :not_found : :success
    })
    checker.run

    document = Mayhem::FrontMatter::Document.load(post_path)
    events = document.front_matter['event_ids'] || []

    refute_includes events, event_filename, 'Event reference should be removed from post'
  end

  def test_post_without_source_url_is_not_checked
    post_path = write_post_without_source_url('2025-01-01-test.md')
    original_content = File.read(post_path)

    checker = build_checker(http_client: ->(_url) { :not_found })
    checker.run

    assert_equal original_content, File.read(post_path), 'Post without source_url should not be modified'
  end

  def test_event_without_source_url_is_not_checked
    event_path = write_event_without_source_url('event123')

    checker = build_checker(http_client: ->(_url) { :not_found })
    checker.run

    assert_path_exists event_path, 'Event without source_url should not be deleted'
  end

  def test_empty_source_url_is_not_checked
    post_path = write_post('2025-01-01-test.md', '')
    original_content = File.read(post_path)

    checker = build_checker(http_client: ->(_url) { :not_found })
    checker.run

    assert_equal original_content, File.read(post_path), 'Post with empty source_url should not be modified'
  end

  def test_multiple_valid_posts_and_events_remain_unchanged
    post1 = write_post('2025-01-01-valid.md', 'https://example.com/valid')
    event1 = write_event('event1', 'https://example.com/event-valid')

    checker = build_checker(http_client: ->(_url) { :success })
    checker.run

    # Valid post should be unchanged
    document1 = Mayhem::FrontMatter::Document.load(post1)

    refute_equal false, document1.front_matter['published']

    # Valid event should exist
    assert_path_exists event1
  end

  def test_multiple_invalid_posts_and_events_are_cleaned_up
    post2 = write_post('2025-01-02-missing.md', 'https://example.com/missing')
    event2 = write_event('event2', 'https://example.com/event-missing')

    checker = build_checker(http_client: ->(_url) { :not_found })
    checker.run

    # Missing post should be unpublished
    document2 = Mayhem::FrontMatter::Document.load(post2)

    refute document2.front_matter['published']

    # Missing event should be deleted
    refute_path_exists event2
  end

  def test_unpublished_post_still_has_published_false_flag
    post_path = write_post('2025-01-01-test.md', 'https://example.com/missing')

    checker = build_checker(http_client: ->(_url) { :not_found })
    checker.run

    document = Mayhem::FrontMatter::Document.load(post_path)

    assert document.front_matter.key?('published'), 'published key should be present'
    refute document.front_matter['published'], 'published should be false'
  end

  def test_multiple_event_references_cleaned_from_single_post
    write_event('event1', 'https://example.com/missing1')
    write_event('event2', 'https://example.com/missing2')
    write_event('event3', 'https://example.com/valid')
    post_path = write_post_with_event_ids('2025-01-01-test.md', 'https://example.com/valid',
                                       %w[event1.md event2.md event3.md])

    checker = build_checker(http_client: lambda { |url|
      url.include?('missing') ? :not_found : :success
    })
    checker.run

    document = Mayhem::FrontMatter::Document.load(post_path)
    events = document.front_matter['event_ids'] || []

    assert_equal ['event3.md'], events, 'Only valid event should remain'
  end

  def test_post_with_only_deleted_events_has_empty_events_array
    write_event('event1', 'https://example.com/missing')
    post_path = write_post_with_event_ids('2025-01-01-test.md', 'https://example.com/valid', ['event1.md'])

    checker = build_checker(http_client: lambda { |url|
      url.include?('missing') ? :not_found : :success
    })
    checker.run

    document = Mayhem::FrontMatter::Document.load(post_path)
    events = document.front_matter['event_ids'] || []

    assert_empty events, 'Events array should be empty'
  end

  def test_invalid_url_scheme_returns_error
    post_path = write_post('2025-01-01-test.md', 'ftp://example.com/file')
    original_content = File.read(post_path)

    # No http_client provided, so real check_url will be used
    checker = build_checker
    checker.run

    assert_equal original_content, File.read(post_path), 'Post should not be modified for invalid scheme'
  end

  def test_malformed_url_returns_error
    post_path = write_post('2025-01-01-test.md', 'not a url at all')
    original_content = File.read(post_path)

    checker = build_checker
    checker.run

    assert_equal original_content, File.read(post_path), 'Post should not be modified for malformed URL'
  end

  private

  def build_checker(http_client: nil, http_status_resolver: nil)
    Mayhem::Content::SourceUrlChecker.new(
      posts_dir: @posts_dir,
      events_dir: @events_dir,
      images_dir: @images_dir,
      assets_dir: @assets_dir,
      logger: @logger,
      http_status_resolver: http_status_resolver || http_client && stub_status_resolver(http_client)
    )
  end

  def stub_status_resolver(http_client)
    Class.new do
      def initialize(http_client)
        @http_client = http_client
      end

      def call(url)
        @http_client.call(url)
      end
    end.new(http_client)
  end

  def write_post(filename, source_url)
    front_matter = {
      'title' => 'Test Post',
      'date' => '2025-01-01T00:00:00Z',
      'source_url' => source_url,
      'image_checksums' => [],
      'topic_titles' => []
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_post_with_image_checksums(filename, source_url, image_checksums)
    front_matter = {
      'title' => 'Test Post',
      'date' => '2025-01-01T00:00:00Z',
      'source_url' => source_url,
      'image_checksums' => image_checksums,
      'topic_titles' => []
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_post_with_event_ids(filename, source_url, event_ids)
    front_matter = {
      'title' => 'Test Post',
      'date' => '2025-01-01T00:00:00Z',
      'source_url' => source_url,
      'image_checksums' => [],
      'event_ids' => event_ids,
      'topic_titles' => []
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_post_without_source_url(filename)
    front_matter = {
      'title' => 'Test Post',
      'date' => '2025-01-01T00:00:00Z',
      'image_checksums' => [],
      'topic_titles' => []
    }
    path = File.join(@posts_dir, filename)
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_event(id, source_url)
    front_matter = {
      'title' => "Event #{id}",
      'start_date' => '2025-12-01T12:00:00Z',
      'source_url' => source_url
    }
    path = File.join(@events_dir, "#{id}.md")
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_event_without_source_url(id)
    front_matter = {
      'title' => "Event #{id}",
      'start_date' => '2025-12-01T12:00:00Z'
    }
    path = File.join(@events_dir, "#{id}.md")
    File.write(path, Mayhem::FrontMatter::Document.build_markdown(front_matter, ''))
    path
  end

  def write_image_metadata(id)
    path = File.join(@images_dir, "#{id}.md")
    File.write(path, "---\nchecksum: #{id}\n---\n")
  end

  def write_asset(id)
    File.write(File.join(@assets_dir, "#{id}.webp"), 'data')
  end
end
