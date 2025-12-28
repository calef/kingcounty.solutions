# frozen_string_literal: true

module Mayhem
  module Support
    class HttpClient
      # Handles reading HTTP response bodies without applying size limits
      class ResponseBodyReader
        def self.read(response)
          return read_streaming(response) if response.respond_to?(:read_body)

          body = response&.body.to_s
          body = body.dup
          body.force_encoding('BINARY')
          body
        end

        def self.read_streaming(response)
          body = +''
          response.read_body do |chunk|
            body << chunk
          end
          body.force_encoding('BINARY')
          body
        end
      end
    end
  end
end
