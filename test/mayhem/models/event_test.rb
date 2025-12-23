# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/event'

class EventModelTest < Minitest::Test
  def test_creates_and_reads_events
    FMRepo::TestHelpers.with_temp_repo(role: :events) do
      record = Mayhem::Models::Event.create!(
        {
          'title' => 'Community Meeting',
          'start_date' => '2025-12-20T09:00:00-08:00',
          'end_date' => '2025-12-20T10:30:00-08:00',
          'feed_content' => '<p>Event details.</p>',
          'feed_content_checksum' => 'abc123',
          'generated_from_post' => '2025-12-01-example',
          'image_ids' => ['https://example.com/image.jpg'],
          'location' => 'Community Center',
          'location_titles' => ['Seattle'],
          'locked' => true,
          'organization_title' => 'Test Organization',
          'original_source_html' => '<div>Original source.</div>',
          'published' => true,
          'source_url' => 'https://example.com/event',
          'summarized' => false,
          'topics' => ['Housing']
        },
        body: 'A test community event.'
      )

      assert_equal '_events/community-meeting.md', record.id
      assert_equal 'Community Meeting', record.title
      assert_equal '2025-12-20T09:00:00-08:00', record.start_date
      assert_equal '2025-12-20T10:30:00-08:00', record.end_date
      assert_equal '<p>Event details.</p>', record.feed_content
      assert_equal 'abc123', record.feed_content_checksum
      assert_equal '2025-12-01-example', record.generated_from_post
      assert_equal false, record.generated_from_post?
      assert_equal ['https://example.com/image.jpg'], record.image_ids
      assert_equal 'Community Center', record.location
      assert_equal ['Seattle'], record.location_titles
      assert_equal true, record.locked
      assert_equal true, record.locked?
      assert_equal 'Test Organization', record.organization_title
      assert_equal '<div>Original source.</div>', record.original_source_html
      assert_equal true, record.published
      assert_equal true, record.published?
      assert_equal 'https://example.com/event', record.source_url
      assert_equal false, record.summarized
      assert_equal false, record.summarized?
      assert_equal ['Housing'], record.topics
      assert_equal 'A test community event.', record.body.strip

      loaded = Mayhem::Models::Event.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Community Meeting', loaded.title
    end
  end

  def test_generated_from_post_predicate
    FMRepo::TestHelpers.with_temp_repo(role: :events) do
      record = Mayhem::Models::Event.create!(
        {
          'title' => 'Generated Event',
          'start_date' => '2025-12-21T09:00:00-08:00',
          'generated_from_post' => true
        },
        body: 'Generated event.'
      )

      assert_equal true, record.generated_from_post?
    end
  end

  def test_locked_predicate_defaults_false
    FMRepo::TestHelpers.with_temp_repo(role: :events) do
      record = Mayhem::Models::Event.create!(
        {
          'title' => 'Unlocked Event',
          'start_date' => '2025-12-22T09:00:00-08:00'
        },
        body: 'Unlocked event.'
      )

      assert_equal false, record.locked?
    end
  end

  def test_published_predicate_defaults_true_and_false_when_unpublished
    FMRepo::TestHelpers.with_temp_repo(role: :events) do
      default_record = Mayhem::Models::Event.create!(
        {
          'title' => 'Default Published',
          'start_date' => '2025-12-23T09:00:00-08:00'
        },
        body: 'Default published.'
      )

      unpublished = Mayhem::Models::Event.create!(
        {
          'title' => 'Unpublished Event',
          'start_date' => '2025-12-24T09:00:00-08:00',
          'published' => false
        },
        body: 'Unpublished event.'
      )

      assert_equal true, default_record.published?
      assert_equal false, unpublished.published?
    end
  end

  def test_summarized_predicate_defaults_false_and_true_when_summarized
    FMRepo::TestHelpers.with_temp_repo(role: :events) do
      default_record = Mayhem::Models::Event.create!(
        {
          'title' => 'Not Summarized',
          'start_date' => '2025-12-25T09:00:00-08:00'
        },
        body: 'Not summarized.'
      )

      summarized = Mayhem::Models::Event.create!(
        {
          'title' => 'Summarized Event',
          'start_date' => '2025-12-26T09:00:00-08:00',
          'summarized' => true
        },
        body: 'Summarized event.'
      )

      assert_equal false, default_record.summarized?
      assert_equal true, summarized.summarized?
    end
  end
end
