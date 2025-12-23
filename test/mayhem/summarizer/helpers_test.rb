# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require 'mayhem/summarizer/helpers'

class SummarizerHelpersTest < Minitest::Test
  class DummySummarizer
    include Mayhem::SummarizerHelpers
  end

  def setup
    @summarizer = DummySummarizer.new
  end

  def test_needs_classification_when_key_missing
    assert @summarizer.send(:needs_classification?, {}, 'topic_titles')
  end

  def test_needs_classification_when_value_nil
    assert @summarizer.send(:needs_classification?, { 'topic_titles' => nil }, 'topic_titles')
  end

  def test_skips_classification_for_empty_array
    refute @summarizer.send(:needs_classification?, { 'topic_titles' => [] }, 'topic_titles')
  end

  def test_skips_classification_when_value_present
    refute @summarizer.send(:needs_classification?, { 'topic_titles' => ['Health'] }, 'topic_titles')
  end
end
