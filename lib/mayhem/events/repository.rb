# frozen_string_literal: true

require_relative '../front_matter/document'

module Mayhem
  module Events
    class Repository
      DEFAULT_DIR = '_events'
      FILE_EXTENSION = '.md'

      attr_reader :directory

      def initialize(directory: DEFAULT_DIR, logger: nil)
        @directory = directory
        @logger = logger
      end

      # Build a file path for an event with date prefix and slug
      def build_path(date_prefix:, slug:)
        file_path("#{date_prefix}-#{slug}")
      end

      # Get the identifier (basename without extension) from a path
      def identifier_from_path(path)
        File.basename(path, FILE_EXTENSION)
      end

      # Iterate over all events, yielding document objects
      def each(&)
        all_paths.each do |path|
          document = load_document(path)
          yield(document, path) if document
        end
      end

      # Get all events as document objects with their paths
      def all
        all_paths.filter_map do |path|
          document = load_document(path)
          [document, path] if document
        end
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

      def load_document(path)
        Mayhem::FrontMatter::Document.load(path, logger: @logger)
      end
    end
  end
end
