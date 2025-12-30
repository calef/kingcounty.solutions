# frozen_string_literal: true

module Mayhem
  module Support
    module ValueNormalizer
      # This file provides utilities for normalizing values across generators.
      # Methods are available as module-level methods (e.g., ValueNormalizer.normalize_value(val))
      # and as instance methods when included (e.g., include ValueNormalizer; normalize_value(val)).

      module_function

      def normalize_value(value)
        return nil if value.nil?

        if value.is_a?(String)
          trimmed = value.strip
          return nil if trimmed.empty?

          trimmed
        elsif value.respond_to?(:empty?) && value.empty?
          nil
        else
          value
        end
      end
    end
  end
end
