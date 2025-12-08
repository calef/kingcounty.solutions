# frozen_string_literal: true

require 'fileutils'

require_relative 'front_matter_document'

module Mayhem
  module Support
    class ImageCleanup
      attr_reader :posts_dir, :images_dir, :assets_dir

      def initialize(posts_dir:, images_dir:, assets_dir:, logger:)
        @posts_dir = posts_dir
        @images_dir = images_dir
        @assets_dir = assets_dir
        @logger = logger
      end

      def collect_image_ids(front_matter)
        Array(front_matter['images']).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def remaining_image_counts(excluded_paths = Set.new)
        counts = Hash.new(0)
        Dir.glob(File.join(@posts_dir, '*.md')).each do |path|
          next if excluded_paths.include?(path)

          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          collect_image_ids(document.front_matter).each { |id| counts[id] += 1 }
        end
        counts
      end

      def cleanup(image_ids, excluded_paths: Set.new)
        remaining_refs = remaining_image_counts(excluded_paths)
        cleanup_images(image_ids, remaining_refs)
      end

      private

      def cleanup_images(image_ids, remaining_refs)
        removed = []
        image_ids.each do |id|
          next if remaining_refs[id]&.positive?

          removed << id
          remove_image_files(id)
        end
        removed
      end

      def remove_image_files(image_id)
        remove_file(File.join(@images_dir, "#{image_id}.md"))
        Dir.glob(File.join(@assets_dir, "#{image_id}.*")).each { |asset| remove_file(asset) }
      end

      def remove_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end
    end
  end
end
