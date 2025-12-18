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
          'parent_location' => 'King County'
        },
        body: 'A test place.'
      )

      assert_equal '_locations/test-place.md', record.id
      assert_equal 'Test Place', record.title
      assert_equal 'City', record.location_type
      assert_equal 'King County', record.parent_location
      assert_equal 'A test place.', record.body.strip

      loaded = Mayhem::Models::Location.find(record.id)
      assert_equal record.id, loaded.id
      assert_equal 'Test Place', loaded.title
    end
  end
end
