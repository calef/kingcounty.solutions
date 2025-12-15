# frozen_string_literal: true

require 'fileutils'

require_relative '../front_matter/document'
require_relative '../images/pruner'

module Mayhem
  module News
    class Pruner
      def initialize(posts_dir:, images_pruner:, logger:)
        @posts_dir = posts_dir
        @images_pruner = images_pruner
        @logger = logger
      end

      def unpublish(path, document)
        front_matter = document.front_matter

        front_matter['published'] = false
        image_ids = @images_pruner.collect_image_ids(front_matter)
        front_matter['images'] = []

        document.front_matter = front_matter
        document.save

        @images_pruner.prune(image_ids, excluded_paths: Set[path]) if image_ids.any?
      end

      def delete(path, document)
        image_ids = @images_pruner.collect_image_ids(document.front_matter)
        delete_file(path)
        @images_pruner.prune(image_ids, excluded_paths: Set[path]) if image_ids.any?
      end

      def prune_images(image_ids, excluded_paths:)
        @images_pruner.prune(image_ids, excluded_paths: excluded_paths)
      end

      def collect_image_ids(front_matter)
        @images_pruner.collect_image_ids(front_matter)
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
