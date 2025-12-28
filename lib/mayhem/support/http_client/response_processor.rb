# frozen_string_literal: true

require 'time'
require 'uri'

module Mayhem
  module Support
    class HttpClient
      # Processes HTTP responses (status codes, headers, error handling)
      class ResponseProcessor
        def initialize(too_many_requests_delay:, logger:)
          @too_many_requests_delay = too_many_requests_delay
          @logger = logger
        end

        def check_status?(response, uri, origin_url:, operation:)
          status_code = response.status.to_i

          raise_too_many_requests(response, uri, origin_url: origin_url, operation: operation) if status_code == 429
          raise NotFoundError.new(url: uri.to_s, origin_url: origin_url, operation: operation, status: status_code) if status_code == 404

          return true if status_code >= 200 && status_code < 300

          raise HttpError.new(url: uri.to_s, origin_url: origin_url, operation: operation, status: status_code, response: response)
        end

        def redirect?(response)
          status = response.status.to_i
          status >= 300 && status < 400
        end

        def extract_redirect_location(response)
          response.headers['location']
        end

        def parse_retry_after(response)
          header = response&.headers&.[]('retry-after')
          parsed = parse_retry_after_value(header)
          wait = parsed || @too_many_requests_delay
          wait = @too_many_requests_delay if wait <= 0
          wait
        end

        private

        def raise_too_many_requests(response, uri, origin_url:, operation:)
          wait = parse_retry_after(response)
          raise TooManyRequestsError.new(
            url: uri.to_s,
            retry_after: wait,
            origin_url: origin_url,
            operation: operation
          )
        end

        def parse_retry_after_value(value)
          return nil unless value

          if value.match?(/\A\d+\z/)
            value.to_i
          else
            (Time.httpdate(value) - Time.now).ceil
          end
        rescue ArgumentError
          nil
        end
      end
    end
  end
end
