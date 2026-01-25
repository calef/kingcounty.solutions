# frozen_string_literal: true

module Mayhem
  # Raised when a network operation fails (HTTP errors, timeouts, connection issues).
  # Wraps low-level network exceptions to provide consistent error handling.
  class NetworkError < StandardError
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
end
