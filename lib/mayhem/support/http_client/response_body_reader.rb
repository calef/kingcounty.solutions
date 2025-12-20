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
              needed = max_bytes - body.bytesize
              break unless needed.positive?

              body << chunk.byteslice(0, [needed, chunk.bytesize].min)
              break if body.bytesize >= max_bytes
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
