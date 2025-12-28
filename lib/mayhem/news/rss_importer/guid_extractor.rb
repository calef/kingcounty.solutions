# frozen_string_literal: true

module Mayhem
  module News
    class RssImporter
      module GuidExtractor
        def extract_guid_text(raw_guid)
          return nil unless raw_guid

          candidate =
            if raw_guid.respond_to?(:content) && raw_guid.content
              raw_guid.content
            elsif raw_guid.respond_to?(:href) && raw_guid.href
              raw_guid.href
            elsif raw_guid.respond_to?(:value) && raw_guid.value
              raw_guid.value
            else
              raw_guid.to_s
            end
          text = candidate.to_s.strip
          text.empty? ? nil : text
        end
      end
    end
  end
end
