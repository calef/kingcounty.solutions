# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/models/topic'

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
end
