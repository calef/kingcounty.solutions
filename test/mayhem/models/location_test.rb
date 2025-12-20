# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/location'

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
end
