# frozen_string_literal: true

require_relative '../../test_helper'
require 'tmpdir'
require 'fileutils'
require 'mayhem/models/topic'

class TopicModelTest < Minitest::Test
  def setup
    @tmp_repo = Dir.mktmpdir('topic_repo')
    @original_repo = Mayhem::Models::Topic.repository
    Mayhem::Models::Topic.repository(@tmp_repo)
  end

  def teardown
    Mayhem::Models::Topic.repository(@original_repo)
    FileUtils.remove_entry(@tmp_repo)
  end

  def test_creates_and_reads_topics
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
