# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'

module Mayhem
  module Support
    class HttpClient
      # Handles raw HTTP transport operations (connections, request execution)
      class HttpTransport
        def initialize(user_agent:, open_timeout:, read_timeout:, allow_insecure_fallback:, logger:, operation_delay_manager:)
          @user_agent = user_agent
          @open_timeout = open_timeout
          @read_timeout = read_timeout
          @allow_insecure_fallback = allow_insecure_fallback
          @logger = logger
          @operation_delay_manager = operation_delay_manager
        end

        def execute_get(uri, accept, operation: nil, &)
          @operation_delay_manager.apply_delay(operation, uri)
          perform_http_request(uri, accept, OpenSSL::SSL::VERIFY_PEER, &)
        rescue OpenSSL::SSL::SSLError => e
          retry_without_verification(uri, accept, e, &)
        rescue Net::HTTPBadResponse => e
          raise unless chunked_response_error?(e)

          @logger.warn "Bad chunked response for #{uri}, retrying with HTTP/1.0"
          perform_http_request(
            uri,
            accept,
            OpenSSL::SSL::VERIFY_PEER,
            http_version: '1.0',
            close_connection: true,
            &
          )
        end

        def execute_head(uri, operation: nil)
          @operation_delay_manager.apply_delay(operation, uri)
          perform_http_head(uri, OpenSSL::SSL::VERIFY_PEER)
        rescue OpenSSL::SSL::SSLError => e
          retry_without_verification_head(uri, e)
        end

        private

        def perform_http_request(uri, accept, verify_mode, http_version: nil, close_connection: false, &block)
          http = build_http_connection(uri, verify_mode)
          response = nil
          http.start do |connection|
            request = build_request(uri, accept, http_version: http_version, close_connection: close_connection)
            response = if block_given?
                         connection.request(request) do |http_response|
                           block.call(http_response)
                         end
                       else
                         connection.request(request)
                       end
          end
          response
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

        def configure_timeouts(http)
          http.read_timeout = @read_timeout
          http.open_timeout = @open_timeout
        end

        def configure_ssl(http, verify_mode)
          return unless http.use_ssl?

          http.verify_mode = verify_mode
          http.cert_store = OpenSSL::X509::Store.new.tap(&:set_default_paths)
        end

        def build_request(uri, accept, http_version: nil, close_connection: false)
          Net::HTTP::Get.new(uri).tap do |request|
            request['User-Agent'] = @user_agent
            request['Accept'] = accept
            request['Accept-Encoding'] = 'identity'
            request['Connection'] = 'close' if close_connection
            request.version = http_version if http_version
          end
        end

        def build_head_request(uri)
          Net::HTTP::Head.new(uri).tap do |request|
            request['User-Agent'] = @user_agent
          end
        end

        def retry_without_verification(uri, accept, error, &)
          return handle_terminal_ssl_error(uri, error) unless @allow_insecure_fallback

          @logger.warn "SSL error (#{error.message}), retrying without verification for #{uri}"
          perform_http_request(uri, accept, OpenSSL::SSL::VERIFY_NONE, &)
        end

        def retry_without_verification_head(uri, error)
          return handle_terminal_ssl_error(uri, error) unless @allow_insecure_fallback

          @logger.warn "SSL error (#{error.message}), retrying HEAD without verification for #{uri}"
          perform_http_head(uri, OpenSSL::SSL::VERIFY_NONE)
        end

        def handle_terminal_ssl_error(uri, error)
          @logger.warn "SSL error for #{uri}: #{error.message}"
          raise error
        end

        def chunked_response_error?(error)
          error.message.to_s.include?('wrong chunk size line')
        end
      end
    end
  end
end
