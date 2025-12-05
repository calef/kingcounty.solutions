# frozen_string_literal: true

module Mayhem
  module Support
    module EncodingUtils
      module_function

      def ensure_utf8(value)
        return '' if value.nil?

        string = value.to_s.dup
        string.force_encoding('UTF-8')
        string.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
      rescue StandardError
        value.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
      end
    end
  end
end
