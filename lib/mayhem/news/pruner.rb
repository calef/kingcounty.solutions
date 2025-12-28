# frozen_string_literal: true

require 'fileutils'

require_relative '../front_matter/document'
require_relative '../images/pruner'
require_relative '../logging'

# TODO: replace use of Mayhem::FrontMatter::Document with respective Mayhem::Models::* classes

module Mayhem
  module News
    class Pruner
      include Mayhem::Loggable

      def initialize(posts_dir:, images_pruner:)
        @posts_dir = posts_dir
        @images_pruner = images_pruner
      end

      def unpublish(path, document)
        front_matter = document.front_matter

        front_matter['published'] = false
        image_checksums = @images_pruner.collect_image_checksums(front_matter)
        front_matter['image_checksums'] = []

        document.front_matter = front_matter
        document.save

        @images_pruner.prune(image_checksums, excluded_paths: Set[path]) if image_checksums.any?
      end

      def delete(path, document)
        image_checksums = @images_pruner.collect_image_checksums(document.front_matter)
        delete_file(path)
        @images_pruner.prune(image_checksums, excluded_paths: Set[path]) if image_checksums.any?
      end

      def prune_images(image_checksums, excluded_paths:)
        @images_pruner.prune(image_checksums, excluded_paths: excluded_paths)
      end

      def collect_image_checksums(front_matter)
        @images_pruner.collect_image_checksums(front_matter)
      end

      private

      def delete_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end
    end
  end
end
