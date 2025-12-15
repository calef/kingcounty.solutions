# frozen_string_literal: true

module Mayhem
  module ImageFiles
    # Repository for image asset files (not markdown metadata).
    # Unlike other repositories, this handles files with varying extensions (.jpg, .png, .webp, etc.)
    # so file_path returns the full path including the filename as-is.
    class Repository
      DEFAULT_DIR = File.join('assets', 'images')

      attr_reader :directory

      def initialize(directory: DEFAULT_DIR)
        @directory = directory
      end

      # Returns the full path for a given filename (which should include the extension)
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
