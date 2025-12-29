# frozen_string_literal: true

require_relative 'document'

module Mayhem
  module FrontMatter
    # Utility helpers for determining whether a Markdown document is purposely hidden.
    module PublishGuard
      extend Mayhem::Loggable

      module_function

      def unpublished?(path)
        return false unless File.exist?(path)

        document = Mayhem::FrontMatter::Document.load(path)
        document && document.front_matter['published'] == false
      rescue StandardError => e
        Mayhem::FrontMatter::PublishGuard.logger.warn("Failed to inspect #{path} for published flag: #{e.message}")
        false
      end
    end
  end
end
