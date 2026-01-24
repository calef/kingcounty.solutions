# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../../test_helper'
require_relative '../../../lib/mayhem/threading/pool_executor'

class PoolExecutorTest < Minitest::Test
  def test_processes_all_items
    executor = Mayhem::Threading::PoolExecutor.new(workers: 2)
    results = []
    mutex = Mutex.new

    executor.run([1, 2, 3, 4, 5]) do |item|
      mutex.synchronize { results << item }
    end

    assert_equal [1, 2, 3, 4, 5].sort, results.sort
  end

  def test_handles_empty_collection
    executor = Mayhem::Threading::PoolExecutor.new(workers: 2)
    results = []

    executor.run([]) do |item|
      results << item
    end

    assert_empty results
  end

  def test_limits_workers_to_item_count
    executor = Mayhem::Threading::PoolExecutor.new(workers: 10)
    thread_ids = []
    mutex = Mutex.new

    executor.run([1, 2]) do |_item|
      mutex.synchronize { thread_ids << Thread.current.object_id }
      sleep 0.01
    end

    # With only 2 items and workers limited to item count,
    # we should see at most 2 unique thread IDs
    assert_operator thread_ids.uniq.size, :<=, 2
  end

  def test_on_error_callback_receives_item_and_exception
    executor = Mayhem::Threading::PoolExecutor.new(workers: 1)
    captured_item = nil
    captured_error = nil

    error_handler = lambda do |item, error|
      captured_item = item
      captured_error = error
    end

    executor.run(['fail_me'], on_error: error_handler) do |_item|
      raise StandardError, 'intentional error'
    end

    assert_equal 'fail_me', captured_item
    assert_instance_of StandardError, captured_error
    assert_equal 'intentional error', captured_error.message
  end

  def test_continues_processing_after_error
    executor = Mayhem::Threading::PoolExecutor.new(workers: 1)
    processed = []
    mutex = Mutex.new

    error_handler = ->(_item, _error) {}

    executor.run([1, 2, 3], on_error: error_handler) do |item|
      raise StandardError, 'boom' if item == 2

      mutex.synchronize { processed << item }
    end

    assert_equal [1, 3], processed.sort
  end

  def test_raises_error_when_no_error_handler_provided
    executor = Mayhem::Threading::PoolExecutor.new(workers: 1)

    assert_raises(StandardError) do
      executor.run(['item']) do |_item|
        raise StandardError, 'unhandled'
      end
    end
  end

  def test_respects_max_workers_override
    executor = Mayhem::Threading::PoolExecutor.new(workers: 10)
    thread_ids = []
    mutex = Mutex.new

    executor.run([1, 2, 3, 4, 5], max_workers: 1) do |_item|
      mutex.synchronize { thread_ids << Thread.current.object_id }
      sleep 0.01
    end

    # With max_workers: 1, all items should be processed by the same thread
    assert_equal 1, thread_ids.uniq.size
  end

  def test_accepts_enumerable
    executor = Mayhem::Threading::PoolExecutor.new(workers: 2)
    results = []
    mutex = Mutex.new

    # Pass a Range (Enumerable) instead of Array
    executor.run(1..3) do |item|
      mutex.synchronize { results << item }
    end

    assert_equal [1, 2, 3], results.sort
  end

  def test_handles_zero_max_workers_override
    executor = Mayhem::Threading::PoolExecutor.new(workers: 10)
    results = []
    mutex = Mutex.new

    # max_workers: 0 should be clamped to 1
    executor.run([1, 2, 3], max_workers: 0) do |item|
      mutex.synchronize { results << item }
    end

    assert_equal [1, 2, 3].sort, results.sort
  end

  def test_handles_negative_max_workers_override
    executor = Mayhem::Threading::PoolExecutor.new(workers: 10)
    results = []
    mutex = Mutex.new

    # max_workers: -5 should be clamped to 1
    executor.run([1, 2, 3], max_workers: -5) do |item|
      mutex.synchronize { results << item }
    end

    assert_equal [1, 2, 3].sort, results.sort
  end

  def test_handles_invalid_max_workers_override
    executor = Mayhem::Threading::PoolExecutor.new(workers: 2)
    results = []
    mutex = Mutex.new

    # max_workers: 'invalid' should fall back to default workers
    executor.run([1, 2, 3], max_workers: 'invalid') do |item|
      mutex.synchronize { results << item }
    end

    assert_equal [1, 2, 3].sort, results.sort
  end
end
