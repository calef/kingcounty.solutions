# frozen_string_literal: true

module Mayhem
  module Topics
    class Repository
      DEFAULT_DIR = '_topics'
      FILE_EXTENSION = '.md'

      attr_reader :directory

      def initialize(directory: DEFAULT_DIR)
        @directory = directory
      end

      def file_path(filename)
        File.join(@directory, "#{filename}#{FILE_EXTENSION}")
      end

      def glob_pattern
        File.join(@directory, "*#{FILE_EXTENSION}")
      end

      def all_file_paths
        Dir.glob(glob_pattern)
      end

      def basename(path)
        File.basename(path, FILE_EXTENSION)
      end
    end
  end
end
