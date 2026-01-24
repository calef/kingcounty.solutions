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

  # --- Threading Edge Case Tests (Issue 5.1) ---

  def test_concurrent_shared_state_access_is_thread_safe
    executor = Mayhem::Threading::PoolExecutor.new(workers: 4)
    counter = { value: 0 }
    mutex = Mutex.new
    iterations = 100

    executor.run((1..iterations).to_a) do |_item|
      # Simulate read-modify-write pattern that would cause race conditions
      # without proper synchronization
      mutex.synchronize do
        current = counter[:value]
        sleep(0.001) # Small delay to increase chance of race condition
        counter[:value] = current + 1
      end
    end

    assert_equal iterations, counter[:value], 'Counter should equal iterations if thread-safe'
  end

  def test_multiple_concurrent_errors_do_not_deadlock
    executor = Mayhem::Threading::PoolExecutor.new(workers: 4)
    error_count = 0
    mutex = Mutex.new

    error_handler = lambda do |_item, _error|
      mutex.synchronize { error_count += 1 }
    end

    # All items will raise errors - should not deadlock
    executor.run([1, 2, 3, 4, 5, 6, 7, 8], on_error: error_handler) do |_item|
      raise StandardError, 'concurrent error'
    end

    assert_equal 8, error_count, 'All errors should be captured'
  end

  def test_stress_test_with_many_items_and_workers
    executor = Mayhem::Threading::PoolExecutor.new(workers: 8)
    results = []
    mutex = Mutex.new
    item_count = 200

    executor.run((1..item_count).to_a) do |item|
      # Simulate variable processing time
      sleep(rand * 0.005)
      mutex.synchronize { results << item }
    end

    assert_equal item_count, results.size, 'All items should be processed'
    assert_equal (1..item_count).to_a.sort, results.sort, 'All items should be present'
  end

  def test_all_threads_complete_before_run_returns
    executor = Mayhem::Threading::PoolExecutor.new(workers: 4)
    completion_times = []
    mutex = Mutex.new

    executor.run([1, 2, 3, 4]) do |_item|
      sleep(0.05)
      mutex.synchronize { completion_times << Time.now }
    end

    run_completed_at = Time.now

    # All completion times should be before run returned
    completion_times.each do |time|
      assert_operator time, :<=, run_completed_at, 'Thread should complete before run returns'
    end
  end

  def test_mixed_success_and_failure_processing
    executor = Mayhem::Threading::PoolExecutor.new(workers: 4)
    successes = []
    failures = []
    success_mutex = Mutex.new
    failure_mutex = Mutex.new

    error_handler = lambda do |item, _error|
      failure_mutex.synchronize { failures << item }
    end

    executor.run((1..20).to_a, on_error: error_handler) do |item|
      raise StandardError, "error for #{item}" if item.even?

      success_mutex.synchronize { successes << item }
    end

    assert_equal 10, successes.size, 'Odd items should succeed'
    assert_equal 10, failures.size, 'Even items should fail'
    assert_equal [1, 3, 5, 7, 9, 11, 13, 15, 17, 19], successes.sort
    assert_equal [2, 4, 6, 8, 10, 12, 14, 16, 18, 20], failures.sort
  end

  def test_queue_drains_completely_under_contention
    executor = Mayhem::Threading::PoolExecutor.new(workers: 10)
    processed = []
    mutex = Mutex.new
    items = (1..50).to_a

    executor.run(items) do |item|
      # Random sleep to create contention
      sleep(rand * 0.01)
      mutex.synchronize { processed << item }
    end

    assert_equal items.sort, processed.sort, 'All items should be processed exactly once'
    assert_equal items.size, processed.size, 'No duplicate processing'
  end

  def test_no_items_lost_when_workers_exceed_items
    executor = Mayhem::Threading::PoolExecutor.new(workers: 100)
    processed = []
    mutex = Mutex.new
    items = [1, 2, 3]

    executor.run(items) do |item|
      mutex.synchronize { processed << item }
    end

    assert_equal items.sort, processed.sort, 'All items processed even with excess workers'
  end

  def test_error_in_one_thread_does_not_affect_others
    executor = Mayhem::Threading::PoolExecutor.new(workers: 4)
    processed = []
    mutex = Mutex.new
    errors_captured = []
    error_mutex = Mutex.new

    error_handler = lambda do |item, error|
      error_mutex.synchronize { errors_captured << { item: item, error: error.message } }
    end

    # Item 5 will raise, but items 1-4 and 6-10 should still process
    executor.run((1..10).to_a, on_error: error_handler) do |item|
      raise StandardError, 'boom' if item == 5

      sleep(0.01) # Give time for concurrent processing
      mutex.synchronize { processed << item }
    end

    assert_equal [1, 2, 3, 4, 6, 7, 8, 9, 10], processed.sort
    assert_equal 1, errors_captured.size
    assert_equal 5, errors_captured.first[:item]
  end
end
