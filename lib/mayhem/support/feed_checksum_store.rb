# frozen_string_literal: true

require 'yaml'

module Mayhem
  module Support
    # Thread-safe cache for RSS feed checksums. Scripts can inject this into
    # services that operate concurrently (like the RSS importer).
    class FeedChecksumStore
      def initialize(path:, logger: nil)
        @path = path
        @logger = logger
        @mutex = Mutex.new
        @data = load_file
        @dirty = false
      end

      def [](key)
        @mutex.synchronize { @data[key] }
      end

      def []=(key, value)
        @mutex.synchronize do
          @data[key] = value
          @dirty = true
        end
      end

      def save
        snapshot = nil
        @mutex.synchronize do
          return unless @dirty

          snapshot = @data.dup
          @dirty = false
        end
        File.write(@path, snapshot.to_yaml)
      end

      private

      def load_file
        return {} unless File.exist?(@path)

        data = YAML.safe_load_file(@path)
        data.is_a?(Hash) ? data : {}
      rescue StandardError => error
        @logger&.warn("Failed to load checksum file #{@path}: #{error.message}")
        {}
      end
    end
  end
end
