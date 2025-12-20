# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/locations/repository'
require 'fmrepo'
require 'mayhem/models/location'

class LocationRepositoryTest < Minitest::Test
  class FakeLogger
    attr_reader :infos, :warns, :errors, :debugs

    def initialize
      @infos = []
      @warns = []
      @errors = []
      @debugs = []
    end

    %i[info warn error debug].each do |level|
      define_method(level) do |message|
        instance_variable_get("@#{level}s") << message
      end
    end
  end

  def setup
    @tmp_root = Dir.mktmpdir('locations')
    @fm_repo = FMRepo::Repository.new(root: @tmp_root)
    @logger = FakeLogger.new
  end

  def teardown
    FileUtils.remove_entry(@tmp_root)
  end

  def create_location(front_matter, body = '')
    Mayhem::Models::Location.create!(front_matter, body:, repo: @fm_repo)
  end

  def test_all_returns_all_locations
    create_location({ 'title' => 'Seattle', 'type' => 'City' }, 'The city of Seattle')
    create_location({ 'title' => 'Bellevue', 'type' => 'City' }, 'The city of Bellevue')

    repository = Mayhem::Locations::Repository.new(
      location_repo: @fm_repo,
      logger: @logger
    )

    locations = repository.all

    assert_equal 2, locations.length
    assert_equal %w[Bellevue Seattle], locations.map { |loc| loc[:title] }.sort
  end

  def test_all_caches_results
    create_location({ 'title' => 'Seattle', 'type' => 'City' }, 'The city of Seattle')

    repository = Mayhem::Locations::Repository.new(
      location_repo: @fm_repo,
      logger: @logger
    )

    first_call = repository.all
    second_call = repository.all

    assert_same first_call, second_call
  end

  def test_build_location_list_formats_locations
    locations = [
      { title: 'Seattle', type: 'City', parent_location_title: nil },
      { title: 'Snoqualmie', type: 'City', parent_location_title: 'Snoqualmie Valley' },
      { title: 'King County', type: 'County', parent_location_title: nil }
    ]

    repository = Mayhem::Locations::Repository.new(
      location_repo: @fm_repo,
      logger: @logger
    )

    result = repository.build_location_list(locations)

    assert_includes result, 'Seattle (City)'
    assert_includes result, 'Snoqualmie (City) in Snoqualmie Valley'
    assert_includes result, 'King County (County)'
  end

  def test_filter_to_highest_level_removes_child_when_parent_present
    locations = [
      { title: 'Snoqualmie Valley', type: 'County Region', parent_location_title: 'Eastside' },
      { title: 'Snoqualmie', type: 'City', parent_location_title: 'Snoqualmie Valley' }
    ]
    titles = ['Snoqualmie Valley', 'Snoqualmie']

    repository = Mayhem::Locations::Repository.new(
      location_repo: @fm_repo,
      logger: @logger
    )

    result = repository.filter_to_highest_level(titles, locations)

    assert_equal ['Snoqualmie Valley'], result
  end

  def test_filter_to_highest_level_keeps_siblings
    locations = [
      { title: 'Snoqualmie Valley', type: 'County Region', parent_location_title: 'Eastside' },
      { title: 'Snoqualmie', type: 'City', parent_location_title: 'Snoqualmie Valley' },
      { title: 'North Bend', type: 'City', parent_location_title: 'Snoqualmie Valley' }
    ]
    titles = ['Snoqualmie', 'North Bend']

    repository = Mayhem::Locations::Repository.new(
      location_repo: @fm_repo,
      logger: @logger
    )

    result = repository.filter_to_highest_level(titles, locations)

    assert_equal ['Snoqualmie', 'North Bend'].sort, result.sort
  end

  def test_filter_to_highest_level_handles_empty_list
    repository = Mayhem::Locations::Repository.new(
      location_repo: @fm_repo,
      logger: @logger
    )

    result = repository.filter_to_highest_level([], [])

    assert_empty result
  end
end
