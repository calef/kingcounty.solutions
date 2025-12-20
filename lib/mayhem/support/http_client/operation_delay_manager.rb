# frozen_string_literal: true

require_relative '../env_utils'

module Mayhem
  module Support
    class HttpClient
      # Manages operation-specific delays for rate limiting
      class OperationDelayManager
        def initialize(host_operation_delays: nil)
          delays_config = host_operation_delays.nil? ? default_operation_host_delays : host_operation_delays
          @operation_host_delays = normalize_operation_host_delays(delays_config)
          @operation_delay_lock = Mutex.new
          @operation_last_request = {}
        end

        def apply_delay(operation, uri)
          return unless operation && uri

          host = uri.host&.downcase
          return unless host

          delay = @operation_host_delays.dig(operation.to_s, host)
          return unless delay

          wait = 0
          key = [operation.to_s, host]
          now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          @operation_delay_lock.synchronize do
            last = @operation_last_request[key]
            earliest = last ? last + delay : now
            wait = [earliest - now, 0].max
            @operation_last_request[key] = now + wait
          end
          sleep(wait) if wait.positive?
        end

        private

        def default_operation_host_delays
          delay = Mayhem::Support::EnvUtils.positive_float('RSS_PUBMED_CANONICAL_HEAD_DELAY', 1.0)
          return {} unless delay

          {
            'canonical_head' => {
              'pubmed.ncbi.nlm.nih.gov' => delay
            }
          }
        end

        def normalize_operation_host_delays(config)
          return {} unless config.is_a?(Hash)

          config.each_with_object({}) do |(operation, hosts), memo|
            op_key = operation.to_s
            next unless hosts.is_a?(Hash)

            memo[op_key] ||= {}
            hosts.each do |host, delay|
              delay_value = delay.to_f
              next unless delay_value.positive?

              host_key = host.to_s.downcase
              next if host_key.empty?

              memo[op_key][host_key] = delay_value
            end
          end
        end
      end
    end
  end
end
