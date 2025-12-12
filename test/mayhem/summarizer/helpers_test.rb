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
    assert @summarizer.send(:needs_classification?, {}, 'topics')
  end

  def test_needs_classification_when_value_nil
    assert @summarizer.send(:needs_classification?, { 'topics' => nil }, 'topics')
  end

  def test_skips_classification_for_empty_array
    refute @summarizer.send(:needs_classification?, { 'topics' => [] }, 'topics')
  end

  def test_skips_classification_when_value_present
    refute @summarizer.send(:needs_classification?, { 'topics' => ['Health'] }, 'topics')
  end
end
