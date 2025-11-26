# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'

module Mayhem
  # Minimal HTTP client that enforces explicit timeouts and redirect limits.
  module HttpFetcher
    DEFAULT_REDIRECT_LIMIT = 5
    FetchContext = Struct.new(:open_timeout, :read_timeout, :headers, :redirect_limit)

    def self.fetch_response(uri_str, open_timeout:, read_timeout:, headers: {}, redirect_limit: DEFAULT_REDIRECT_LIMIT)
      uri = parse_uri(uri_str)
      context = FetchContext.new(open_timeout, read_timeout, headers, redirect_limit)
      request = build_request(uri, headers)

      make_request(uri, request, context)
    end

    def self.parse_uri(uri_str)
      raise ArgumentError, 'unsupported URI' unless uri_str

      uri = URI.parse(uri_str)
      raise ArgumentError, "unsupported scheme #{uri.scheme}" unless uri.is_a?(URI::HTTP)

      uri
    end

    def self.build_request(uri, headers)
      request = Net::HTTP::Get.new(uri)
      headers.each { |key, value| request[key] = value }
      request
    end

    def self.make_request(uri, request, context)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        http.open_timeout = context.open_timeout
        http.read_timeout = context.read_timeout
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER if http.use_ssl?
        handle_response(http.request(request), uri, context)
      end
    end

    def self.handle_response(response, uri, context)
      return response if response.is_a?(Net::HTTPSuccess)
      return follow_redirect(response, uri, context) if response.is_a?(Net::HTTPRedirection)

      response
    end

    def self.follow_redirect(response, uri, context)
      location = response['location']
      raise "redirect missing location header for #{uri}" unless location

      raise 'too many redirects' if context.redirect_limit <= 0

      redirect_uri = URI.join(uri, location).to_s
      fetch_response(redirect_uri,
                     open_timeout: context.open_timeout,
                     read_timeout: context.read_timeout,
                     headers: context.headers,
                     redirect_limit: context.redirect_limit - 1)
    end

    private_class_method :handle_response, :follow_redirect, :parse_uri, :build_request, :make_request
  end
end
