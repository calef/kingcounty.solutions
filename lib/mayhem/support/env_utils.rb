# frozen_string_literal: true

module Mayhem
  module Support
    module EnvUtils
      module_function

      def positive_float(name, default)
        raw = ENV.fetch(name, nil)
        value = if raw.nil?
                  default
                else
                  Float(raw)
                end
        value.positive? ? value : nil
      rescue StandardError
        default.positive? ? default : nil
      end
    end
  end
end
