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
        post.image_checksums = []
        post.save!

        @images_pruner.prune(image_checksums, excluded_posts: [post]) if image_checksums.any?
      end

      def delete(post)
        return unless post

        image_checksums = @images_pruner.collect_image_checksums(post)
        post_id = post.id.to_s
        post.destroy

        @images_pruner.prune(image_checksums, excluded_posts: [post_id]) if image_checksums.any?
      end

      def prune_images(image_checksums, excluded_posts:)
        @images_pruner.prune(image_checksums, excluded_posts: excluded_posts)
      end
    end
  end
end
