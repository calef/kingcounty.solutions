# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require_relative '../../lib/mayhem/support/env_utils'

class EnvUtilsTest < Minitest::Test
  def setup
    @prev = ENV['EXAMPLE_FLOAT']
  end

  def teardown
    if @prev.nil?
      ENV.delete('EXAMPLE_FLOAT')
    else
      ENV['EXAMPLE_FLOAT'] = @prev
    end
  end

  def test_positive_float_returns_default_when_missing
    ENV.delete('EXAMPLE_FLOAT')
    assert_in_delta 1.5, Mayhem::Support::EnvUtils.positive_float('EXAMPLE_FLOAT', 1.5), 0.0001
  end

  def test_positive_float_returns_nil_when_non_positive
    ENV['EXAMPLE_FLOAT'] = '0'
    assert_nil Mayhem::Support::EnvUtils.positive_float('EXAMPLE_FLOAT', 1.5)
  end

  def test_positive_float_parses_value
    ENV['EXAMPLE_FLOAT'] = '2.75'
    assert_in_delta 2.75, Mayhem::Support::EnvUtils.positive_float('EXAMPLE_FLOAT', 1.5), 0.0001
  end

  def test_positive_float_falls_back_on_parse_error
    ENV['EXAMPLE_FLOAT'] = 'abc'
    assert_in_delta 1.5, Mayhem::Support::EnvUtils.positive_float('EXAMPLE_FLOAT', 1.5), 0.0001
  end
end
