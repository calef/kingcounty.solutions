# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/location'
require 'mayhem/models/news'
require 'mayhem/models/event'

class LocationModelTest < Minitest::Test
  def test_creates_and_reads_locations
    FMRepo::TestHelpers.with_temp_repo(role: :locations) do
      record = Mayhem::Models::Location.create!(
        {
          'title' => 'Test Place',
          'type' => 'City',
          'parent_location_title' => 'King County'
        },
        body: 'A test place.'
      )

      assert_equal '_locations/test-place.md', record.id
      assert_equal 'Test Place', record.title
      assert_equal 'City', record.location_type
      assert_equal 'King County', record.parent_location_title
      assert_equal 'A test place.', record.body.strip

      loaded = Mayhem::Models::Location.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Test Place', loaded.title
    end
  end

  def test_parent_location_returns_matching_location
    FMRepo::TestHelpers.with_temp_repo(role: :locations) do
      parent = Mayhem::Models::Location.create!(
        { 'title' => 'King County', 'type' => 'County' },
        body: 'The county.'
      )
      child = Mayhem::Models::Location.create!(
        { 'title' => 'Test Place', 'parent_location_title' => 'King County' },
        body: 'A test place.'
      )

      assert_equal parent.id, child.parent_location.id
      assert_equal 'King County', child.parent_location.title
      assert child.parent_location?
    end
  end

  def test_parent_location_handles_missing_parent
    FMRepo::TestHelpers.with_temp_repo(role: :locations) do
      child = Mayhem::Models::Location.create!(
        { 'title' => 'Solo', 'parent_location_title' => 'Missing' },
        body: 'A solo place.'
      )

      assert_nil child.parent_location
      refute child.parent_location?
    end
  end

  def test_parent_location_handles_blank_parent_title
    FMRepo::TestHelpers.with_temp_repo(role: :locations) do
      child = Mayhem::Models::Location.create!(
        { 'title' => 'Solo' },
        body: 'A solo place.'
      )

      assert_nil child.parent_location
      refute child.parent_location?
    end
  end

  def test_finds_related_news_and_events
    FMRepo::TestHelpers.with_temp_repo(role: :locations) do
      FMRepo::TestHelpers.with_temp_repo(role: :news) do
        FMRepo::TestHelpers.with_temp_repo(role: :events) do
          location = Mayhem::Models::Location.create!(
            { 'title' => ' White Center ', 'type' => 'Neighborhood' },
            body: 'A neighborhood.'
          )
          other_location = Mayhem::Models::Location.create!(
            { 'title' => 'Seattle', 'type' => 'City' },
            body: 'A city.'
          )

          news = Mayhem::Models::News.create!(
            {
              'title' => 'White Center Update',
              'date' => '2025-06-23T17:54:03+00:00',
              'organization_title' => 'Neighborhood Office',
              'location_titles' => ['White Center'],
              'summarized' => true
            },
            body: 'News for White Center.'
          )
          other_news = Mayhem::Models::News.create!(
            {
              'title' => 'Seattle Update',
              'date' => '2025-06-24T10:00:00+00:00',
              'organization_title' => 'City Office',
              'location_titles' => ['Seattle'],
              'summarized' => true
            },
            body: 'News for Seattle.'
          )

          event = Mayhem::Models::Event.create!(
            {
              'title' => 'White Center Event',
              'start_date' => '2025-12-20T09:00:00-08:00',
              'organization_title' => 'Neighborhood Office',
              'location_titles' => [' White Center ']
            },
            body: 'Event for White Center.'
          )
          other_event = Mayhem::Models::Event.create!(
            {
              'title' => 'Seattle Event',
              'start_date' => '2025-12-21T09:00:00-08:00',
              'organization_title' => 'City Office',
              'location_titles' => ['Seattle']
            },
            body: 'Event for Seattle.'
          )

          assert_equal [news.id], location.news.map(&:id).sort
          assert_equal [event.id], location.events.map(&:id).sort
          assert_equal [other_news.id], other_location.news.map(&:id).sort
          assert_equal [other_event.id], other_location.events.map(&:id).sort
        end
      end
    end
  end
end
