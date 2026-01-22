# frozen_string_literal: true

require 'seldon'

require_relative '../images/pruner'
require_relative '../models/news'

module Mayhem
  module News
    class Pruner
      include Seldon::Loggable

      def initialize(images_pruner:)
        @images_pruner = images_pruner
      end

      def unpublish(post)
        post.published = false
        image_checksums = @images_pruner.collect_image_checksums(post)
        post_id = post.id.to_s
        post.image_checksums = []
        post.save!

        @images_pruner.prune(image_checksums, excluded_post_ids: [post_id]) if image_checksums.any?
      end

      def delete(post)
        return unless post

        image_checksums = @images_pruner.collect_image_checksums(post)
        post_id = post.id.to_s
        post.destroy

        @images_pruner.prune(image_checksums, excluded_post_ids: [post_id]) if image_checksums.any?
      end

      def prune_images(image_checksums, excluded_post_ids:)
        @images_pruner.prune(image_checksums, excluded_post_ids: excluded_post_ids)
      end
    end
  end
end
