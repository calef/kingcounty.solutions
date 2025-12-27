# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/topic'
require 'mayhem/models/organization'
require 'mayhem/models/news'
require 'mayhem/models/event'

class TopicModelTest < Minitest::Test
  def test_creates_and_reads_topics
    FMRepo::TestHelpers.with_temp_repo(role: :topics) do
      record = Mayhem::Models::Topic.create!(
        { 'title' => 'Housing' },
        body: 'Housing support details.'
      )

      assert_equal '_topics/housing.md', record.id
      assert_equal 'Housing', record.title
      assert_equal 'Housing support details.', record.body.strip

      loaded = Mayhem::Models::Topic.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Housing', loaded.title
    end
  end

  def test_finds_related_content
    FMRepo::TestHelpers.with_temp_repo(role: :topics) do
      FMRepo::TestHelpers.with_temp_repo(role: :organizations) do
        FMRepo::TestHelpers.with_temp_repo(role: :news) do
          FMRepo::TestHelpers.with_temp_repo(role: :events) do
            topic = Mayhem::Models::Topic.create!(
              { 'title' => 'Housing' },
              body: 'Housing support details.'
            )
            other_topic = Mayhem::Models::Topic.create!(
              { 'title' => 'Transit' },
              body: 'Transit updates.'
            )

            org = Mayhem::Models::Organization.create!(
              { 'title' => 'Housing Office', 'type' => 'Agency', 'topic_titles' => ['Housing'] },
              body: 'Housing org.'
            )
            other_org = Mayhem::Models::Organization.create!(
              { 'title' => 'Transit Office', 'type' => 'Agency', 'topic_titles' => ['Transit'] },
              body: 'Transit org.'
            )

            news = Mayhem::Models::News.create!(
              {
                'title' => 'Housing News',
                'date' => '2025-06-23T17:54:03+00:00',
                'organization_title' => 'Housing Office',
                'topic_titles' => ['Housing'],
                'summarized' => true
              },
              body: 'Housing news.'
            )
            other_news = Mayhem::Models::News.create!(
              {
                'title' => 'Transit News',
                'date' => '2025-06-24T10:00:00+00:00',
                'organization_title' => 'Transit Office',
                'topic_titles' => ['Transit'],
                'summarized' => true
              },
              body: 'Transit news.'
            )

            event = Mayhem::Models::Event.create!(
              {
                'title' => 'Housing Event',
                'start_date' => '2025-12-20T09:00:00-08:00',
                'organization_title' => 'Housing Office',
                'topic_titles' => ['Housing']
              },
              body: 'Housing event.'
            )
            other_event = Mayhem::Models::Event.create!(
              {
                'title' => 'Transit Event',
                'start_date' => '2025-12-21T09:00:00-08:00',
                'organization_title' => 'Transit Office',
                'topic_titles' => ['Transit']
              },
              body: 'Transit event.'
            )

            assert_equal [org.id], topic.organizations.map(&:id).sort
            assert_equal [news.id], topic.news.map(&:id).sort
            assert_equal [event.id], topic.events.map(&:id).sort
            assert_equal [other_org.id], other_topic.organizations.map(&:id).sort
            assert_equal [other_news.id], other_topic.news.map(&:id).sort
            assert_equal [other_event.id], other_topic.events.map(&:id).sort
          end
        end
      end
    end
  end
end
