# frozen_string_literal: true

require 'uri'
require_relative '../url_utils'
require_relative 'response_body_reader'

module Mayhem
  module Support
    class HttpClient
      # Orchestrates HTTP request flow including redirects
      class RequestFlow
        include Mayhem::Loggable

        def initialize(transport:, response_processor:, max_redirects:)
          @transport = transport
          @response_processor = response_processor
          @max_redirects = max_redirects
        end

        def fetch_with_redirects(url, accept, origin_url:, operation:)
          perform_request(url, accept, @max_redirects, origin_url: origin_url, operation: operation)
        end

        def resolve_head_redirects(uri, origin_url:, operation:)
          follow_head_redirect(uri, @max_redirects, origin_url: origin_url, operation: operation)
        end

        private

        def perform_request(url, accept, remaining_redirects, origin_url:, operation:)
          uri = URI.parse(url)
          body = nil
          redirect = nil
          status_checked = false
          response = @transport.execute_get(uri, accept, operation: operation) do |http_response|
            redirect = @response_processor.redirect?(http_response)
            unless redirect
              @response_processor.check_status?(http_response, uri, origin_url: origin_url, operation: operation)
              status_checked = true
              body = ResponseBodyReader.read(http_response)
            end
          end

          redirect = @response_processor.redirect?(response) if redirect.nil?
          if redirect
            return follow_redirect(
              response,
              uri,
              accept,
              remaining_redirects,
              origin_url: origin_url,
              operation: operation
            )
          end

          @response_processor.check_status?(response, uri, origin_url: origin_url, operation: operation) unless status_checked
          body = ResponseBodyReader.read(response) if body.nil?

          [
            response,
            {
              body: body,
              content_type: response.headers['content-type'],
              final_url: uri.to_s
            }
          ]
        end

        def follow_redirect(response, uri, accept, remaining_redirects, origin_url:, operation:)
          raise 'Too many redirects' if remaining_redirects <= 0

          location = @response_processor.extract_redirect_location(response)
          raise 'Redirect missing location header' unless location

          new_url = Mayhem::Support::UrlUtils.absolutize(uri.to_s, location) || location
          perform_request(
            new_url,
            accept,
            remaining_redirects - 1,
            origin_url: origin_url,
            operation: operation
          )
        end

        def follow_head_redirect(uri, remaining_redirects, origin_url:, operation:)
          response = @transport.execute_head(uri, operation: operation)
          status_code = response&.status&.to_i

          # Check for 429 before processing redirect
          @response_processor.check_status?(response, uri, origin_url: origin_url, operation: operation) if status_code == 429

          if @response_processor.redirect?(response)
            raise 'Too many redirects' if remaining_redirects <= 0

            location = @response_processor.extract_redirect_location(response)
            return { url: uri.to_s, status: status_code } unless location

            new_url = Mayhem::Support::UrlUtils.absolutize(uri.to_s, location) || location
            new_uri = URI.parse(new_url)
            follow_head_redirect(
              new_uri,
              remaining_redirects - 1,
              origin_url: origin_url,
              operation: operation
            )
          else
            { url: uri.to_s, status: status_code }
          end
        end
      end
    end
  end
end
