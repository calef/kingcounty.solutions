# frozen_string_literal: true

require 'seldon'

module Mayhem
  module Pruners
    # Base class for content pruners that handle unpublishing and deleting
    # records while properly cleaning up associated images.
    #
    # Subclasses must implement:
    # - exclusion_key: Returns the keyword argument name for image pruning
    #   (e.g., :excluded_post_ids or :excluded_event_ids)
    class Base
      include Seldon::Loggable

      def initialize(images_pruner:)
        @images_pruner = images_pruner
      end

      def unpublish(record)
        record.published = false
        image_checksums = @images_pruner.collect_image_checksums(record)
        record_id = record.id.to_s
        record.image_checksums = []
        record.save!

        prune_images_if_any(image_checksums, record_id)
      end

      def delete(record)
        return unless record

        image_checksums = @images_pruner.collect_image_checksums(record)
        record_id = record.id.to_s
        record.destroy

        prune_images_if_any(image_checksums, record_id)
        after_delete(record_id)
      end

      def prune_images(image_checksums, **exclusion_args)
        @images_pruner.prune(image_checksums, **exclusion_args)
      end

      private

      # Subclasses must implement this to return the exclusion keyword
      # (e.g., :excluded_post_ids or :excluded_event_ids)
      def exclusion_key
        raise NotImplementedError, "#{self.class} must implement #exclusion_key"
      end

      # Hook for subclasses to perform additional cleanup after deletion.
      # Default implementation does nothing.
      def after_delete(record_id); end

      def prune_images_if_any(image_checksums, record_id)
        return unless image_checksums.any?

        @images_pruner.prune(image_checksums, exclusion_key => [record_id])
      end
    end
  end
end
