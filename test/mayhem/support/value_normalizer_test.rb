# frozen_string_literal: true

require_relative '../../test_helper'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/support/value_normalizer'

class ValueNormalizerTest < Minitest::Test
  def test_normalize_value_with_nil
    assert_nil Mayhem::Support::ValueNormalizer.normalize_value(nil)
  end

  def test_normalize_value_with_string
    assert_equal 'foo', Mayhem::Support::ValueNormalizer.normalize_value('  foo  ')
    assert_equal 'bar', Mayhem::Support::ValueNormalizer.normalize_value('bar')
  end

  def test_normalize_value_with_empty_string
    assert_nil Mayhem::Support::ValueNormalizer.normalize_value('')
    assert_nil Mayhem::Support::ValueNormalizer.normalize_value('   ')
  end

  def test_normalize_value_with_empty_array
    assert_nil Mayhem::Support::ValueNormalizer.normalize_value([])
  end

  def test_normalize_value_with_non_empty_array
    assert_equal [1, 2, 3], Mayhem::Support::ValueNormalizer.normalize_value([1, 2, 3])
  end

  def test_normalize_value_with_empty_hash
    assert_nil Mayhem::Support::ValueNormalizer.normalize_value({})
  end

  def test_normalize_value_with_non_empty_hash
    assert_equal({ foo: 'bar' }, Mayhem::Support::ValueNormalizer.normalize_value({ foo: 'bar' }))
  end

  def test_normalize_value_with_number
    assert_equal 42, Mayhem::Support::ValueNormalizer.normalize_value(42)
    assert_equal 3.14, Mayhem::Support::ValueNormalizer.normalize_value(3.14)
  end

  def test_normalize_value_with_boolean
    assert_equal true, Mayhem::Support::ValueNormalizer.normalize_value(true)
    assert_equal false, Mayhem::Support::ValueNormalizer.normalize_value(false)
  end
end
