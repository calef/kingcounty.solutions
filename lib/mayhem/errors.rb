# frozen_string_literal: true

module Mayhem
  # Custom exception for application-level network operation failures.
  # Use this class to raise custom network errors in your code.
  # To rescue low-level network exceptions, use the EXCEPTIONS constant.
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
