# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/image'
require 'mayhem/models/news'
require 'mayhem/models/event'

class ImageModelTest < Minitest::Test
  def test_creates_and_reads_images
    FMRepo::TestHelpers.with_temp_repo(role: :images) do
      record = Mayhem::Models::Image.create!(
        {
          'checksum' => 'abc123',
          'date' => '2025-12-20T07:54:25+00:00',
          'image_url' => '/assets/images/abc123.webp',
          'organization_title' => 'Test Source',
          'source_url' => 'https://example.com/image.png',
          'title' => 'Test Image'
        },
        body: ''
      )

      assert_equal '_images/abc123.md', record.id
      assert_equal 'abc123', record.checksum
      assert_equal '2025-12-20T07:54:25+00:00', record.date
      assert_equal '/assets/images/abc123.webp', record.image_url
      assert_equal 'Test Source', record.organization_title
      assert_equal 'https://example.com/image.png', record.source_url
      assert_equal 'Test Image', record.title

      loaded = Mayhem::Models::Image.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Test Image', loaded.title
      assert_equal 'abc123', loaded.checksum
    end
  end

  def test_finds_related_news_and_events
    FMRepo::TestHelpers.with_temp_repo(role: :images) do
      FMRepo::TestHelpers.with_temp_repo(role: :news) do
        FMRepo::TestHelpers.with_temp_repo(role: :events) do
          image = Mayhem::Models::Image.create!(
            {
              'checksum' => 'abc123',
              'date' => '2025-12-20T07:54:25+00:00',
              'image_url' => '/assets/images/abc123.webp',
              'organization_title' => 'Test Source',
              'source_url' => 'https://example.com/image.png',
              'title' => 'Test Image'
            },
            body: ''
          )
          other_image = Mayhem::Models::Image.create!(
            {
              'checksum' => 'def456',
              'date' => '2025-12-21T07:54:25+00:00',
              'image_url' => '/assets/images/def456.webp',
              'organization_title' => 'Other Source',
              'source_url' => 'https://example.com/other.png',
              'title' => 'Other Image'
            },
            body: ''
          )

          news = Mayhem::Models::News.create!(
            {
              'title' => 'Test News',
              'date' => '2025-06-23T17:54:03+00:00',
              'organization_title' => 'Test Source',
              'image_checksums' => [image.checksum],
              'summarized' => true
            },
            body: 'Test news.'
          )
          other_news = Mayhem::Models::News.create!(
            {
              'title' => 'Other News',
              'date' => '2025-06-24T10:00:00+00:00',
              'organization_title' => 'Other Source',
              'image_checksums' => [other_image.checksum],
              'summarized' => true
            },
            body: 'Other news.'
          )

          event = Mayhem::Models::Event.create!(
            {
              'title' => 'Test Event',
              'start_date' => '2025-12-20T09:00:00-08:00',
              'organization_title' => 'Test Source',
              'image_checksums' => [image.checksum]
            },
            body: 'Test event.'
          )
          other_event = Mayhem::Models::Event.create!(
            {
              'title' => 'Other Event',
              'start_date' => '2025-12-21T09:00:00-08:00',
              'organization_title' => 'Other Source',
              'image_checksums' => [other_image.checksum]
            },
            body: 'Other event.'
          )

          assert_equal [news.id], image.news.map(&:id).sort
          assert_equal [event.id], image.events.map(&:id).sort
          assert_equal [other_news.id], other_image.news.map(&:id).sort
          assert_equal [other_event.id], other_image.events.map(&:id).sort
        end
      end
    end
  end
end
