# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/news'

class NewsModelTest < Minitest::Test
  def test_creates_and_reads_news
    FMRepo::TestHelpers.with_temp_repo(role: :news) do
      record = Mayhem::Models::News.create!(
        {
          'title' => 'Test News Article',
          'date' => '2025-06-23T17:54:03+00:00',
          'source' => 'Test Organization',
          'source_url' => 'https://example.com/article',
          'topics' => ['Health Care', 'Education & Learning'],
          'locations' => ['King County'],
          'image_ids' => [],
          'events' => [],
          'events_extracted' => true,
          'feed_content' => 'Test feed content',
          'feed_content_checksum' => 'feed-checksum',
          'locked' => true,
          'original_source_html' => '<p>Original source</p>',
          'rss_guid' => 'rss-guid-123',
          'summarized' => true
        },
        body: 'This is a test news article body.'
      )

      assert_equal '_posts/2025-06-23-test-news-article.md', record.id
      assert_equal 'Test News Article', record.title
      assert_equal '2025-06-23T17:54:03+00:00', record.date
      assert_equal 'Test Organization', record.source
      assert_equal 'https://example.com/article', record.source_url
      assert_equal ['Health Care', 'Education & Learning'], record.topics
      assert_equal ['King County'], record.locations
      assert_equal [], record.image_ids
      assert_equal [], record.events
      assert_equal true, record.events_extracted
      assert record.events_extracted?
      assert_equal 'Test feed content', record.feed_content
      assert_equal 'feed-checksum', record.feed_content_checksum
      assert_equal true, record.locked
      assert record.locked?
      assert_equal '<p>Original source</p>', record.original_source_html
      assert_equal 'rss-guid-123', record.rss_guid
      assert_equal true, record.summarized
      assert record.summarized?
      assert record.published?
      assert_equal 'This is a test news article body.', record.body.strip

      loaded = Mayhem::Models::News.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Test News Article', loaded.title
      assert_equal '2025-06-23T17:54:03+00:00', loaded.date
    end
  end

  def test_creates_news_with_date_object
    FMRepo::TestHelpers.with_temp_repo(role: :news) do
      date_obj = Time.parse('2025-07-15T12:00:00+00:00')
      record = Mayhem::Models::News.create!(
        {
          'title' => 'Another Test Article',
          'date' => date_obj,
          'source' => 'Test Source',
          'summarized' => true
        },
        body: 'Article with date object.'
      )

      assert_equal '_posts/2025-07-15-another-test-article.md', record.id
      assert_equal 'Another Test Article', record.title
    end
  end

  def test_published_default_is_true
    FMRepo::TestHelpers.with_temp_repo(role: :news) do
      record = Mayhem::Models::News.create!(
        {
          'title' => 'Published Article',
          'date' => '2025-06-23T10:00:00+00:00',
          'source' => 'Test Source',
          'summarized' => true
        },
        body: 'Published by default.'
      )

      assert record.published?
    end
  end

  def test_unpublished_when_explicitly_set
    FMRepo::TestHelpers.with_temp_repo(role: :news) do
      record = Mayhem::Models::News.create!(
        {
          'title' => 'Unpublished Article',
          'date' => '2025-06-23T10:00:00+00:00',
          'source' => 'Test Source',
          'published' => false,
          'summarized' => true
        },
        body: 'Explicitly unpublished.'
      )

      assert_equal false, record.published
      refute record.published?
    end
  end

  def test_finds_existing_news_posts
    FMRepo::TestHelpers.with_temp_repo(role: :news) do
      # Create a few test records
      Mayhem::Models::News.create!(
        {
          'title' => 'First Article',
          'date' => '2025-06-20T10:00:00+00:00',
          'source' => 'Source A',
          'summarized' => true
        },
        body: 'First article content.'
      )

      Mayhem::Models::News.create!(
        {
          'title' => 'Second Article',
          'date' => '2025-06-21T10:00:00+00:00',
          'source' => 'Source B',
          'summarized' => true
        },
        body: 'Second article content.'
      )

      all_news = Mayhem::Models::News.all.to_a
      assert_equal 2, all_news.size
      titles = all_news.map(&:title).sort
      assert_equal ['First Article', 'Second Article'], titles
    end
  end
end
