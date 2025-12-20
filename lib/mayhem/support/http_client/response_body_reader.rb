# frozen_string_literal: true

module Mayhem
  module Support
    class HttpClient
      # Handles reading HTTP response bodies with optional size limits
      class ResponseBodyReader
        def self.read(response, max_bytes)
          body = +''
          response.read_body do |chunk|
            if max_bytes.positive?
              next if body.bytesize >= max_bytes

              needed = max_bytes - body.bytesize
              body << chunk.byteslice(0, needed)
            else
              body << chunk
            end
          end
          body.force_encoding('BINARY')
          body
        end
      end
    end
  end
end
