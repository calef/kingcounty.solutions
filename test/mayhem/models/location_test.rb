# frozen_string_literal: true

require_relative '../../test_helper'
require 'tmpdir'
require 'fileutils'
require 'mayhem/models/location'

class LocationModelTest < Minitest::Test
  def setup
    @tmp_repo = Dir.mktmpdir('location_repo')
    @original_repo = Mayhem::Models::Location.repository
    Mayhem::Models::Location.repository(@tmp_repo)
  end

  def teardown
    Mayhem::Models::Location.repository(@original_repo)
    FileUtils.remove_entry(@tmp_repo)
  end

  def test_creates_and_reads_locations
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
