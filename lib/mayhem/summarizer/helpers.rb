# frozen_string_literal: true

module Mayhem
  module SummarizerHelpers
    private

    def needs_classification?(front_matter, key)
      # An explicit empty array means the content was already classified, so we should not retry.
      return true unless front_matter.key?(key)

      front_matter[key].nil?
    end
  end
end
