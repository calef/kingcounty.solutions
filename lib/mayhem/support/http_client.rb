# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'
require 'time'
require 'nokogiri'
require 'open-uri'
require 'mayhem/logging'
require_relative 'env_utils'

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
        OpenURI::HTTPError,
        SocketError,
        Net::OpenTimeout,
        Net::ReadTimeout,
        Timeout::Error,
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
        delays_config = host_operation_delays.nil? ? default_operation_host_delays : host_operation_delays
        @operation_host_delays = normalize_operation_host_delays(delays_config)
        @operation_delay_lock = Mutex.new
        @operation_last_request = {}
      end

      def fetch(url, accept:, max_bytes:)
        attempt = 0
        begin
          attempt += 1
          _response, payload = perform_request(
            url,
            accept,
            max_bytes,
            @max_redirects,
            origin_url: url,
            operation: 'content_fetch'
          )
          sleep @delay
        rescue TooManyRequestsError => e
          raise if attempt >= @max_retries

          wait = e.retry_after || @too_many_requests_delay
          log_too_many_requests_backoff(e, wait, attempt: attempt, max_attempts: @max_retries)
          sleep wait
          retry
        rescue *RETRYABLE_ERRORS => e
          raise if attempt >= @max_retries

          wait = @retry_initial_delay * (@retry_backoff_factor**(attempt - 1))
          @logger.warn(
            "Retrying #{url} after #{e.class} (#{e.message}) in #{format('%.2f', wait)}s " \
            "(attempt #{attempt}/#{@max_retries})"
          )
          sleep wait
          retry
        end
        payload
      end

      def resolve_final_url(url)
        attempt = 0
        begin
          attempt += 1
          uri = URI.parse(url)
          result = follow_head_redirect(uri, @max_redirects, origin_url: url, operation: 'canonical_head')
          return unless result

          status = result[:status]
          return result[:url] if status && status >= 200 && status < 300

          @logger.debug "Skipping canonical redirect for #{url} due to status #{status}" if status
          nil
        rescue TooManyRequestsError => e
          raise if attempt >= @max_retries

          wait = e.retry_after || @too_many_requests_delay
          log_too_many_requests_backoff(e, wait, attempt: attempt, max_attempts: @max_retries)
          sleep wait
          retry
        rescue *RETRYABLE_ERRORS => e
          raise if attempt >= @max_retries

          wait = @retry_initial_delay * (@retry_backoff_factor**(attempt - 1))
          @logger.warn(
            "Retrying HEAD #{url} after #{e.class} (#{e.message}) in #{format('%.2f', wait)}s " \
            "(attempt #{attempt}/#{@max_retries})"
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

      def response_for(url, accept: HTML_ACCEPT, max_bytes: 0)
        attempt = 0
        begin
          attempt += 1
          response, payload = perform_request(
            url,
            accept,
            max_bytes,
            @max_redirects,
            origin_url: url,
            operation: 'status_check'
          )
          {
            status: response.code.to_i,
            final_url: payload[:final_url],
            response: response
          }
        rescue NotFoundError => e
          {
            status: e.status || 404,
            final_url: e.url || url,
            response: nil
          }
        rescue TooManyRequestsError => e
          raise if attempt >= @max_retries

          wait = e.retry_after || @too_many_requests_delay
          log_too_many_requests_backoff(e, wait, attempt: attempt, max_attempts: @max_retries)
          sleep wait
          retry
        rescue *RETRYABLE_ERRORS => e
          raise if attempt >= @max_retries

          wait = @retry_initial_delay * (@retry_backoff_factor**(attempt - 1))
          @logger.warn(
            "Retrying #{url} after #{e.class} (#{e.message}) in #{format('%.2f', wait)}s " \
            "(attempt #{attempt}/#{@max_retries})"
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

      def perform_request(url, accept, max_bytes, remaining_redirects, origin_url:, operation:)
        uri = URI.parse(url)
        response, body = execute_request(uri, accept, max_bytes, operation: operation)
        status_code = response.code.to_i
        if response.is_a?(Net::HTTPRedirection)
          return follow_redirect(
            response,
            uri,
            accept,
            max_bytes,
            remaining_redirects,
            origin_url: origin_url,
            operation: operation
          )
        end
        raise_too_many_requests(response, uri, origin_url: origin_url, operation: operation) if status_code == 429
        raise NotFoundError.new(url: uri.to_s, origin_url: origin_url, operation: operation, status: status_code) if status_code == 404

        raise OpenURI::HTTPError.new("#{response.code} #{response.message} for #{uri}", response) unless response.is_a?(Net::HTTPSuccess)

        [
          response,
          {
            body: body,
            content_type: response['content-type'],
            final_url: uri.to_s
          }
        ]
      end

      def execute_request(uri, accept, max_bytes, verify_mode: OpenSSL::SSL::VERIFY_PEER, retried: false, operation: nil)
        apply_operation_delay(operation, uri)
        perform_http_request(uri, accept, max_bytes, verify_mode)
      rescue OpenSSL::SSL::SSLError => e
        retry_without_verification(uri, accept, max_bytes, retried, e, operation: operation)
      end

      def execute_head_request(uri, verify_mode: OpenSSL::SSL::VERIFY_PEER, retried: false, operation: nil)
        apply_operation_delay(operation, uri)
        perform_http_head(uri, verify_mode)
      rescue OpenSSL::SSL::SSLError => e
        retry_without_verification_head(uri, retried, e, operation: operation)
      end

      def follow_redirect(response, uri, accept, max_bytes, remaining_redirects, origin_url:, operation:)
        raise 'Too many redirects' if remaining_redirects <= 0

        location = response['location']
        raise 'Redirect missing location header' unless location

        new_url = Mayhem::Support::UrlUtils.absolutize(uri.to_s, location) || location
        perform_request(
          new_url,
          accept,
          max_bytes,
          remaining_redirects - 1,
          origin_url: origin_url,
          operation: operation
        )
      end

      def configure_timeouts(http)
        http.read_timeout = @read_timeout
        http.open_timeout = @open_timeout
      end

      def configure_ssl(http, verify_mode)
        return unless http.use_ssl?

        http.verify_mode = verify_mode
        http.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
      end

      def perform_http_request(uri, accept, max_bytes, verify_mode)
        http = build_http_connection(uri, verify_mode)
        response = nil
        body = nil
        http.start do |connection|
          request = build_request(uri, accept)
          response = connection.request(request) { |res| body = read_response_body(res, max_bytes) }
        end

        [response, body]
      end

      def perform_http_head(uri, verify_mode)
        http = build_http_connection(uri, verify_mode)
        response = nil
        http.start do |connection|
          request = build_head_request(uri)
          response = connection.request(request)
        end
        response
      end

      def build_http_connection(uri, verify_mode)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.use_ssl = uri.scheme == 'https'
          configure_timeouts(http)
          configure_ssl(http, verify_mode)
        end
      end

      def retry_without_verification(uri, accept, max_bytes, retried, error, operation: nil)
        return handle_terminal_ssl_error(uri, error) unless @allow_insecure_fallback && !retried

        @logger.warn "SSL error (#{error.message}), retrying without verification for #{uri}"
        execute_request(
          uri,
          accept,
          max_bytes,
          verify_mode: OpenSSL::SSL::VERIFY_NONE,
          retried: true,
          operation: operation
        )
      end

      def handle_terminal_ssl_error(uri, error)
        @logger.warn "SSL error for #{uri}: #{error.message}"
        raise error
      end

      def build_request(uri, accept)
        Net::HTTP::Get.new(uri).tap do |request|
          request['User-Agent'] = @user_agent
          request['Accept'] = accept
          request['Accept-Encoding'] = 'identity'
        end
      end

      def build_head_request(uri)
        Net::HTTP::Head.new(uri).tap do |request|
          request['User-Agent'] = @user_agent
        end
      end

      def read_response_body(response, max_bytes)
        body = +''
        response.read_body do |chunk|
          if max_bytes.positive?
            next if body.bytesize >= max_bytes

            needed = max_bytes - body.bytesize
            body << chunk.byteslice(0, needed)
          else
            body << chunk
          end
        end
        body.force_encoding('BINARY')
        body
      end

      def retry_without_verification_head(uri, retried, error, operation: nil)
        return handle_terminal_ssl_error(uri, error) unless @allow_insecure_fallback && !retried

        @logger.warn "SSL error (#{error.message}), retrying HEAD without verification for #{uri}"
        execute_head_request(
          uri,
          verify_mode: OpenSSL::SSL::VERIFY_NONE,
          retried: true,
          operation: operation
        )
      end

      def follow_head_redirect(uri, remaining_redirects, origin_url:, operation:, verify_mode: OpenSSL::SSL::VERIFY_PEER)
        response = execute_head_request(uri, verify_mode: verify_mode, operation: operation)
        status_code = response&.code&.to_i
        raise_too_many_requests(response, uri, origin_url: origin_url, operation: operation) if status_code == 429
        if response.is_a?(Net::HTTPRedirection)
          raise 'Too many redirects' if remaining_redirects <= 0

          location = response['location']
          return { url: uri.to_s, status: status_code } unless location

          new_url = Mayhem::Support::UrlUtils.absolutize(uri.to_s, location) || location
          new_uri = URI.parse(new_url)
          follow_head_redirect(
            new_uri,
            remaining_redirects - 1,
            verify_mode: verify_mode,
            origin_url: origin_url,
            operation: operation
          )
        else
          { url: uri.to_s, status: status_code }
        end
      end

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

      def raise_too_many_requests(response, uri, origin_url:, operation:)
        wait = too_many_requests_delay(response)
        raise TooManyRequestsError.new(
          url: uri.to_s,
          retry_after: wait,
          origin_url: origin_url,
          operation: operation
        )
      end

      def too_many_requests_delay(response)
        header = response&.[]('retry-after')
        parsed = parse_retry_after(header)
        wait = parsed || @too_many_requests_delay
        wait = @too_many_requests_delay if wait <= 0
        wait
      end

      def parse_retry_after(value)
        return nil unless value

        if value.match?(/\A\d+\z/)
          value.to_i
        else
          (Time.httpdate(value) - Time.now).ceil
        end
      rescue ArgumentError
        nil
      end

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

      def apply_operation_delay(operation, uri)
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
    end
  end
end
