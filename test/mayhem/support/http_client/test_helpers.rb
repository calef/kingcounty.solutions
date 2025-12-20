# frozen_string_literal: true

# Shared test helpers for HttpClient tests
module HttpClientTestHelpers
  class FakeLogger
    attr_reader :warns, :debugs, :infos

    def initialize
      @warns = []
      @debugs = []
      @infos = []
    end

    def warn(message)
      @warns << message
    end

    def debug(message)
      @debugs << message
    end

    def info(message)
      @infos << message
    end
  end

  class FakeResponse
    def initialize(code, headers = {}, redirect: false)
      @code = code
      @headers = headers
      @redirect = redirect
    end

    def code
      @code
    end

    def [](key)
      @headers[key]
    end

    def is_a?(klass)
      return true if klass == Net::HTTPRedirection && @redirect

      super
    end
  end

  class FakeHttp
    attr_reader :started, :request
    attr_accessor :use_ssl, :read_timeout, :open_timeout, :verify_mode, :cert_store

    def initialize(response)
      @response = response
      @started = false
    end

    def start
      @started = true
      yield self
    end

    def request(_request)
      @request = _request
      @response
    end

    def use_ssl?
      !!@use_ssl
    end
  end

  class FakeResponseStream
    def initialize(chunks)
      @chunks = chunks
    end

    def read_body
      @chunks.each { |chunk| yield chunk }
    end
  end
end
