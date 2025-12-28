# frozen_string_literal: true

require 'uri'
require 'mayhem/logging'
require_relative 'env_utils'
require_relative 'http_client/response_body_reader'
require_relative 'http_client/http_transport'
require_relative 'http_client/response_processor'
require_relative 'http_client/request_flow'
require_relative 'http_client/operation_delay_manager'

module Mayhem
  module Support
    require_relative 'url_utils'

    class HttpClient
      UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) AppleWebKit/537.36 ' \
           '(KHTML, like Gecko) Chrome/125.0 Safari/537.36'
      HTML_ACCEPT = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'

      DEFAULTS = {
        delay: 0.15,
        max_redirects: 5,
        timeout: 30,
        allow_insecure_fallback: true,
        max_retries: 3,
        retry_initial_delay: 0.5,
        retry_backoff_factor: 2.0,
        too_many_requests_delay: 60
      }.freeze

      RETRYABLE_ERRORS = [
        Faraday::ConnectionFailed,
        Faraday::TimeoutError,
        SocketError,
        Timeout::Error,
        EOFError,
        Errno::ECONNRESET,
        Errno::ECONNREFUSED,
        Errno::EHOSTUNREACH,
        Errno::ETIMEDOUT
      ].freeze

      class TooManyRequestsError < StandardError
        attr_reader :retry_after, :url, :origin_url, :operation

        def initialize(url:, retry_after:, origin_url:, operation:)
          super("HTTP 429 Too Many Requests for #{url}")
          @url = url
          @retry_after = retry_after
          @origin_url = origin_url
          @operation = operation
        end
      end

      class NotFoundError < StandardError
        attr_reader :url, :origin_url, :operation, :status

        def initialize(url:, origin_url:, operation:, status: 404)
          super("HTTP #{status} for #{url}")
          @url = url
          @origin_url = origin_url
          @operation = operation
          @status = status
        end
      end

      class ForbiddenError < StandardError
        attr_reader :url, :origin_url, :operation, :status

        def initialize(url:, origin_url:, operation:, status: 403)
          super("HTTP #{status} for #{url}")
          @url = url
          @origin_url = origin_url
          @operation = operation
          @status = status
        end
      end

      class HttpError < StandardError
        attr_reader :url, :origin_url, :operation, :status, :response

        def initialize(url:, origin_url:, operation:, status:, response: nil)
          super("HTTP #{status} for #{url}")
          @url = url
          @origin_url = origin_url
          @operation = operation
          @status = status
          @response = response
        end
      end

      class ForbiddenError < HttpError
        def initialize(url:, origin_url:, operation:, status: 403, response: nil)
          super(url: url, origin_url: origin_url, operation: operation, status: status, response: response)
        end
      end

      def initialize(user_agent: UA, delay: DEFAULTS[:delay], max_redirects: DEFAULTS[:max_redirects],
                     timeout: nil, open_timeout: nil, read_timeout: nil,
                     max_retries: DEFAULTS[:max_retries],
                     retry_initial_delay: DEFAULTS[:retry_initial_delay],
                     retry_backoff_factor: DEFAULTS[:retry_backoff_factor],
                     allow_insecure_fallback: DEFAULTS[:allow_insecure_fallback],
                     too_many_requests_delay: DEFAULTS[:too_many_requests_delay],
                     host_operation_delays: nil,
                     logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
        @user_agent = user_agent
        @delay = delay
        @max_redirects = max_redirects
        base_timeout = timeout || DEFAULTS[:timeout]
        @open_timeout = open_timeout || base_timeout
        @read_timeout = read_timeout || base_timeout
        @allow_insecure_fallback = allow_insecure_fallback
        @logger = logger
        @max_retries = [max_retries.to_i, 1].max
        @retry_initial_delay = retry_initial_delay
        @retry_backoff_factor = retry_backoff_factor
        @too_many_requests_delay = too_many_requests_delay

        @operation_delay_manager = OperationDelayManager.new(host_operation_delays: host_operation_delays)
        @transport = HttpTransport.new(
          user_agent: @user_agent,
          open_timeout: @open_timeout,
          read_timeout: @read_timeout,
          allow_insecure_fallback: @allow_insecure_fallback,
          logger: @logger,
          operation_delay_manager: @operation_delay_manager
        )
        @response_processor = ResponseProcessor.new(
          too_many_requests_delay: @too_many_requests_delay,
          logger: @logger
        )
        @request_flow = RequestFlow.new(
          transport: @transport,
          response_processor: @response_processor,
          max_redirects: @max_redirects,
          logger: @logger
        )
      end

      def fetch(url, accept:)
        attempt = 0
        max_attempts = @max_retries + 1
        begin
          attempt += 1
          _response, payload = @request_flow.fetch_with_redirects(
            url,
            accept,
            origin_url: url,
            operation: 'content_fetch'
          )
          sleep @delay
        rescue ForbiddenError => e
          @logger.warn "Access forbidden (HTTP 403) for #{url}, not retrying"
          raise
        rescue TooManyRequestsError => e
          raise if attempt > @max_retries

          wait = e.retry_after || @too_many_requests_delay
          log_too_many_requests_backoff(e, wait, attempt: attempt, max_attempts: max_attempts)
          sleep wait
          retry
        rescue *RETRYABLE_ERRORS => e
          raise if attempt > @max_retries

          wait = @retry_initial_delay * (@retry_backoff_factor**(attempt - 1))
          @logger.warn(
            "Retrying #{url} after #{e.class} (#{e.message}) in #{format('%.2f', wait)}s " \
            "(attempt #{attempt}/#{max_attempts})"
          )
          sleep wait
          retry
        end
        payload
      end

      def resolve_final_url(url)
        attempt = 0
        max_attempts = @max_retries + 1
        begin
          attempt += 1
          uri = URI.parse(url)
          result = @request_flow.resolve_head_redirects(uri, origin_url: url, operation: 'canonical_head')
          return unless result

          status = result[:status]
          return result[:url] if status && status >= 200 && status < 300

          @logger.debug "Skipping canonical redirect for #{url} due to status #{status}" if status
          nil
        rescue ForbiddenError => e
          @logger.debug "Access forbidden (HTTP 403) for #{url}, not retrying"
          nil
        rescue TooManyRequestsError => e
          raise if attempt > @max_retries

          wait = e.retry_after || @too_many_requests_delay
          log_too_many_requests_backoff(e, wait, attempt: attempt, max_attempts: max_attempts)
          sleep wait
          retry
        rescue *RETRYABLE_ERRORS => e
          raise if attempt > @max_retries

          wait = @retry_initial_delay * (@retry_backoff_factor**(attempt - 1))
          @logger.warn(
            "Retrying HEAD #{url} after #{e.class} (#{e.message}) in #{format('%.2f', wait)}s " \
            "(attempt #{attempt}/#{max_attempts})"
          )
          sleep wait
          retry
        rescue URI::InvalidURIError => e
          @logger.debug "Invalid URI for canonical resolution (#{url}): #{e.message}"
          nil
        rescue StandardError => e
          @logger.debug "Failed to resolve canonical URL for #{url}: #{e.message}"
          nil
        end
      end

      def response_for(url, accept: HTML_ACCEPT)
        attempt = 0
        max_attempts = @max_retries + 1
        begin
          attempt += 1
          response, payload = @request_flow.fetch_with_redirects(
            url,
            accept,
            origin_url: url,
            operation: 'status_check'
          )
          {
            status: response.status.to_i,
            final_url: payload[:final_url],
            response: response
          }
        rescue ForbiddenError => e
          @logger.debug "Access forbidden (HTTP 403) for #{url}, not retrying"
          {
            status: 403,
            final_url: e.url || url,
            response: nil
          }
        rescue NotFoundError => e
          {
            status: e.status || 404,
            final_url: e.url || url,
            response: nil
          }
        rescue TooManyRequestsError => e
          raise if attempt > @max_retries

          wait = e.retry_after || @too_many_requests_delay
          log_too_many_requests_backoff(e, wait, attempt: attempt, max_attempts: max_attempts)
          sleep wait
          retry
        rescue *RETRYABLE_ERRORS => e
          raise if attempt > @max_retries

          wait = @retry_initial_delay * (@retry_backoff_factor**(attempt - 1))
          @logger.warn(
            "Retrying #{url} after #{e.class} (#{e.message}) in #{format('%.2f', wait)}s " \
            "(attempt #{attempt}/#{max_attempts})"
          )
          sleep wait
          retry
        rescue URI::InvalidURIError => e
          @logger.debug "Invalid URI while checking status (#{url}): #{e.message}"
          nil
        rescue StandardError => e
          @logger.debug "Failed to check status for #{url}: #{e.message}"
          nil
        end
      end

      private

      def log_too_many_requests_backoff(error, wait, attempt:, max_attempts:)
        operation = error.operation || 'unknown'
        origin = error.origin_url || 'unknown'
        request = error.url || 'unknown'
        @logger.warn(
          "Backoff after 429 during #{operation} " \
          "(origin=#{origin}, request=#{request}) for #{format('%.2f', wait)}s " \
          "(attempt #{attempt}/#{max_attempts})"
        )
      end
    end
  end
end
