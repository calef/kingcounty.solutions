# frozen_string_literal: true

module Mayhem
  module ImageFiles
    class Repository
      DEFAULT_DIR = File.join('assets', 'images')

      attr_reader :directory

      def initialize(directory: DEFAULT_DIR)
        @directory = directory
      end

      def file_path(filename)
        File.join(@directory, filename)
      end

      def glob_pattern(extension = nil)
        pattern = extension ? "*#{extension}" : '*'
        File.join(@directory, pattern)
      end

      def all_file_paths(extension = nil)
        Dir.glob(glob_pattern(extension))
      end
    end
  end
end
