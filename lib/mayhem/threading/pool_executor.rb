# frozen_string_literal: true

module Mayhem
  module Threading
    # A simple thread pool executor for processing items in parallel.
    #
    # Usage:
    #   executor = PoolExecutor.new(workers: 4)
    #   executor.run(items) { |item| process(item) }
    #
    # With error handling:
    #   executor.run(items, on_error: ->(item, e) { log(e) }) { |item| process(item) }
    #
    # The executor creates a queue of items and spawns worker threads
    # to process them. Each worker pops items from the queue until empty.
    class PoolExecutor
      def initialize(workers:)
        @workers = [workers, 1].max
      end

      # Process items in parallel using the configured number of workers.
      #
      # @param items [Enumerable] Items to process
      # @param max_workers [Integer, nil] Override max workers for this run
      # @param on_error [Proc, nil] Called with (item, exception) when processing fails
      # @yield [item] Block called for each item
      def run(items, max_workers: nil, on_error: nil, &)
        items = items.to_a
        return if items.empty?

        worker_count = determine_worker_count(items.size, max_workers)
        queue = build_queue(items)

        threads = spawn_workers(worker_count, queue, on_error, &)
        threads.each(&:join)
      end

      private

      def determine_worker_count(item_count, max_override)
        effective_max = max_override || @workers
        [item_count, effective_max].min
      end

      def build_queue(items)
        queue = Queue.new
        items.each { |item| queue << item }
        queue
      end

      def spawn_workers(count, queue, on_error)
        Array.new(count) do
          Thread.new do
            loop do
              item = queue.pop(true)
              yield(item)
            rescue ThreadError
              break
            rescue StandardError => e
              raise unless on_error

              on_error.call(item, e)
            end
          end
        end
      end
    end
  end
end
