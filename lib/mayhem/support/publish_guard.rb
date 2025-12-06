# frozen_string_literal: true

require_relative 'front_matter_document'

module Mayhem
  module Support
    # Utility helpers for determining whether a Markdown document is purposely hidden.
    module PublishGuard
      module_function

      def unpublished?(path, logger: nil)
        return false unless File.exist?(path)

        document = Mayhem::Support::FrontMatterDocument.load(path, logger:)
        document && document.front_matter['published'] == false
      rescue StandardError => e
        logger&.warn("Failed to inspect #{path} for published flag: #{e.message}")
        false
      end
    end
  end
end
