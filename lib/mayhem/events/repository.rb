# frozen_string_literal: true

module Mayhem
  module Events
    class Repository
      DEFAULT_DIR = '_events'
      FILE_EXTENSION = '.md'

      attr_reader :directory

      def initialize(directory: DEFAULT_DIR)
        @directory = directory
      end

      # Build a file path for an event with date prefix and slug
      def build_path(date_prefix:, slug:)
        file_path("#{date_prefix}-#{slug}")
      end

      # Get the identifier (basename without extension) from a path
      def identifier_from_path(path)
        File.basename(path, FILE_EXTENSION)
      end

      # Iterate over all events
      def each(&)
        all_paths.each(&)
      end

      # Get all event paths
      def all
        all_paths
      end

      # Get all file paths (for backward compatibility)
      def all_file_paths
        all_paths
      end

      # Legacy method for backward compatibility
      def file_path(filename)
        File.join(@directory, "#{filename}#{FILE_EXTENSION}")
      end

      # Legacy method for backward compatibility
      def basename(path)
        identifier_from_path(path)
      end

      private

      def glob_pattern
        File.join(@directory, "*#{FILE_EXTENSION}")
      end

      def all_paths
        Dir.glob(glob_pattern)
      end
    end
  end
end
