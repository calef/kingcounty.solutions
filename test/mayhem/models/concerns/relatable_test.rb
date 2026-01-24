# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../../test_helper'
require_relative '../../../../lib/mayhem/models/concerns/relatable'

class RelatableTest < Minitest::Test
  class TestRecord
    include Mayhem::Models::Concerns::Relatable

    attr_accessor :title, :checksum

    def initialize(title: nil, checksum: nil)
      @title = title
      @checksum = checksum
    end

    # Expose private method for testing
    def public_find_related_records(model, match_key:, target_field:, array_field: true)
      find_related_records(model, match_key: match_key, target_field: target_field, array_field: array_field)
    end
  end

  class MockRecord
    attr_accessor :topic_titles, :organization_title, :image_checksums

    def initialize(topic_titles: [], organization_title: nil, image_checksums: [])
      @topic_titles = topic_titles
      @organization_title = organization_title
      @image_checksums = image_checksums
    end
  end

  class MockModel
    def self.all
      @all ||= []
    end

    def self.all=(records)
      @all = records
    end
  end

  def setup
    MockModel.all = []
  end

  def test_find_related_records_returns_empty_when_match_key_is_blank
    record = TestRecord.new(title: '')
    MockModel.all = [MockRecord.new(topic_titles: ['Health'])]

    result = record.public_find_related_records(MockModel, match_key: :title, target_field: :topic_titles)

    assert_empty result
  end

  def test_find_related_records_returns_empty_when_match_key_is_nil
    record = TestRecord.new(title: nil)
    MockModel.all = [MockRecord.new(topic_titles: ['Health'])]

    result = record.public_find_related_records(MockModel, match_key: :title, target_field: :topic_titles)

    assert_empty result
  end

  def test_find_related_records_matches_array_field
    record = TestRecord.new(title: 'Health')
    matching = MockRecord.new(topic_titles: %w[Health Safety])
    non_matching = MockRecord.new(topic_titles: ['Education'])
    MockModel.all = [matching, non_matching]

    result = record.public_find_related_records(MockModel, match_key: :title, target_field: :topic_titles)

    assert_equal [matching], result
  end

  def test_find_related_records_matches_scalar_field
    record = TestRecord.new(title: 'City of Seattle')
    matching = MockRecord.new(organization_title: 'City of Seattle')
    non_matching = MockRecord.new(organization_title: 'King County')
    MockModel.all = [matching, non_matching]

    result = record.public_find_related_records(
      MockModel,
      match_key: :title,
      target_field: :organization_title,
      array_field: false
    )

    assert_equal [matching], result
  end

  def test_find_related_records_handles_whitespace_in_match_key
    record = TestRecord.new(title: '  Health  ')
    matching = MockRecord.new(topic_titles: ['Health'])
    MockModel.all = [matching]

    result = record.public_find_related_records(MockModel, match_key: :title, target_field: :topic_titles)

    assert_equal [matching], result
  end

  def test_find_related_records_handles_whitespace_in_array_values
    record = TestRecord.new(title: 'Health')
    matching = MockRecord.new(topic_titles: ['  Health  ', 'Safety'])
    MockModel.all = [matching]

    result = record.public_find_related_records(MockModel, match_key: :title, target_field: :topic_titles)

    assert_equal [matching], result
  end

  def test_find_related_records_works_with_checksum
    record = TestRecord.new(checksum: 'abc123')
    matching = MockRecord.new(image_checksums: %w[abc123 def456])
    non_matching = MockRecord.new(image_checksums: ['xyz789'])
    MockModel.all = [matching, non_matching]

    result = record.public_find_related_records(MockModel, match_key: :checksum, target_field: :image_checksums)

    assert_equal [matching], result
  end

  def test_find_related_records_returns_multiple_matches
    record = TestRecord.new(title: 'Health')
    matching1 = MockRecord.new(topic_titles: ['Health'])
    matching2 = MockRecord.new(topic_titles: %w[Health Safety])
    non_matching = MockRecord.new(topic_titles: ['Education'])
    MockModel.all = [matching1, matching2, non_matching]

    result = record.public_find_related_records(MockModel, match_key: :title, target_field: :topic_titles)

    assert_equal [matching1, matching2], result
  end
end
