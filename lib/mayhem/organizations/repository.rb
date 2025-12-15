# frozen_string_literal: true

module Mayhem
  module Organizations
    class Repository
      DEFAULT_DIR = '_organizations'
      FILE_EXTENSION = '.md'

      attr_reader :directory

      def initialize(directory: DEFAULT_DIR)
        @directory = directory
      end

      # Get the identifier (basename without extension) from a path
      def identifier_from_path(path)
        File.basename(path, FILE_EXTENSION)
      end

      # Iterate over all organizations
      def each(&)
        all_paths.each(&)
      end

      # Get all organization paths
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
