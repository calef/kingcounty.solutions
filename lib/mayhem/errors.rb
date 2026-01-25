# frozen_string_literal: true

module Mayhem
  # Base error class for all Mayhem-specific errors.
  class Error < StandardError; end

  # Raised when a network operation fails (HTTP errors, timeouts, connection issues).
  # Wraps low-level network exceptions to provide consistent error handling.
  class NetworkError < Error
    attr_reader :cause

    def initialize(message = nil, cause: nil)
      @cause = cause
      super(message || cause&.message || 'Network error')
    end

    # Low-level exception classes that represent network errors.
    # Use this constant when rescuing network-related exceptions.
    EXCEPTIONS = [
      Faraday::Error,
      SocketError,
      Timeout::Error,
      EOFError,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      Errno::EHOSTUNREACH,
      Errno::ETIMEDOUT
    ].freeze
  end

  # Raised when content fetching fails (404, HTTP errors, etc.).
  class FetchError < NetworkError; end

  # Raised when content is not found (404 responses).
  class NotFoundError < FetchError; end

  # Raised when parsing fails (YAML, iCal, HTML, etc.).
  class ParseError < Error; end
end
