# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'
require 'nokogiri'
require 'open-uri'
require 'mayhem/logging'

module Mayhem
  module Support
    require_relative 'url_utils'

    class HttpClient
      UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_0) AppleWebKit/537.36 ' \
           '(KHTML, like Gecko) Chrome/125.0 Safari/537.36'

      DEFAULTS = {
        delay: 0.15,
        max_redirects: 5,
        timeout: 30,
        allow_insecure_fallback: true,
        max_retries: 3,
        retry_initial_delay: 0.5,
        retry_backoff_factor: 2.0
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

      def initialize(user_agent: UA, delay: DEFAULTS[:delay], max_redirects: DEFAULTS[:max_redirects],
                     timeout: nil, open_timeout: nil, read_timeout: nil,
                     max_retries: DEFAULTS[:max_retries],
                     retry_initial_delay: DEFAULTS[:retry_initial_delay],
                     retry_backoff_factor: DEFAULTS[:retry_backoff_factor],
                     allow_insecure_fallback: DEFAULTS[:allow_insecure_fallback],
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
      end

      def fetch(url, accept:, max_bytes:)
        attempt = 0
        begin
          attempt += 1
          response = perform_request(url, accept, max_bytes, @max_redirects)
          sleep @delay
          response
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
      end

      private

      def perform_request(url, accept, max_bytes, remaining_redirects)
        uri = URI.parse(url)
        response, body = execute_request(uri, accept, max_bytes)
        if response.is_a?(Net::HTTPRedirection)
          return follow_redirect(response, uri, accept, max_bytes, remaining_redirects)
        end

        {
          body: body,
          content_type: response['content-type'],
          final_url: uri.to_s
        }
      end

      def execute_request(uri, accept, max_bytes, verify_mode: OpenSSL::SSL::VERIFY_PEER, retried: false)
        perform_http_request(uri, accept, max_bytes, verify_mode)
      rescue OpenSSL::SSL::SSLError => e
        retry_without_verification(uri, accept, max_bytes, retried, e)
      end

      def follow_redirect(response, uri, accept, max_bytes, remaining_redirects)
        raise 'Too many redirects' if remaining_redirects <= 0

        location = response['location']
        raise 'Redirect missing location header' unless location

        new_url = Mayhem::Support::UrlUtils.absolutize(uri.to_s, location) || location
        perform_request(new_url, accept, max_bytes, remaining_redirects - 1)
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

      def build_http_connection(uri, verify_mode)
        Net::HTTP.new(uri.host, uri.port).tap do |http|
          http.use_ssl = uri.scheme == 'https'
          configure_timeouts(http)
          configure_ssl(http, verify_mode)
        end
      end

      def retry_without_verification(uri, accept, max_bytes, retried, error)
        return handle_terminal_ssl_error(uri, error) unless @allow_insecure_fallback && !retried

        @logger.warn "SSL error (#{error.message}), retrying without verification for #{uri}"
        execute_request(
          uri,
          accept,
          max_bytes,
          verify_mode: OpenSSL::SSL::VERIFY_NONE,
          retried: true
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

      def read_response_body(response, max_bytes)
        body = +''
        response.read_body do |chunk|
          next if body.bytesize >= max_bytes

          needed = max_bytes - body.bytesize
          body << chunk.byteslice(0, needed)
        end
        body.force_encoding('BINARY')
        body
      end
    end
  end
end
