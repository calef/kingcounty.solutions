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
    attr_reader :status, :headers, :body

    def initialize(status, headers = {}, body: '')
      @status = status
      @headers = headers
      @body = body
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

  class FakeRequest
    attr_reader :headers

    def initialize
      @headers = {}
    end
  end
end
