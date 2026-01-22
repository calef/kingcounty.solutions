# frozen_string_literal: true

require 'fileutils'
require 'seldon'

require_relative '../models/event'
require_relative '../models/image'
require_relative '../models/news'

module Mayhem
  module Images
    class Pruner
      include Seldon::Loggable

      def collect_image_checksums(record)
        Array(record.image_checksums).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def remaining_image_counts(excluded_posts: [], excluded_events: [])
        counts = Hash.new(0)
        excluded_post_ids = build_exclusion_set(excluded_posts)
        excluded_event_ids = build_exclusion_set(excluded_events)

        Mayhem::Models::News.all.each do |post|
          next if excluded_post_ids.include?(record_identifier(post))

          collect_image_checksums(post).each { |id| counts[id] += 1 }
        end

        Mayhem::Models::Event.all.each do |event|
          next if excluded_event_ids.include?(record_identifier(event))

          collect_image_checksums(event).each { |id| counts[id] += 1 }
        end

        counts
      end

      def prune(image_checksums, excluded_posts: [], excluded_events: [])
        remaining_refs = remaining_image_counts(excluded_posts: excluded_posts, excluded_events: excluded_events)
        prune_images(image_checksums, remaining_refs)
      end

      private

      def build_exclusion_set(records)
        Set.new(Array(records).compact.map { |r| record_identifier(r) })
      end

      def record_identifier(record)
        return record.to_s if record.is_a?(String)

        record.id.to_s
      end

      def prune_images(image_checksums, remaining_refs)
        removed = []
        image_checksums.each do |checksum|
          next if remaining_refs[checksum]&.positive?

          removed << checksum
          delete_image(checksum)
        end
        removed
      end

      def delete_image(checksum)
        image = Mayhem::Models::Image.find_by(checksum: checksum)
        return delete_orphaned_assets(checksum) unless image

        delete_image_asset(image)
        image.destroy
      end

      def delete_image_asset(image)
        if image.image_url
          asset_path = image.image_url.sub(%r{\A/}, '')
          full_path = File.join(repo_root, asset_path)
          FileUtils.rm(full_path)
        else
          # Fall back to checksum-based pattern if image_url is not set
          delete_orphaned_assets(image.checksum)
        end
      rescue Errno::ENOENT
        # Asset already removed
      end

      def delete_orphaned_assets(checksum)
        # Handle case where image metadata is missing but asset files exist
        pattern = File.join(repo_root, 'assets', 'images', "#{checksum}.*")
        Dir.glob(pattern).each do |path|
          FileUtils.rm(path)
        rescue Errno::ENOENT
          # Already removed
        end
      end

      def repo_root
        Mayhem::Models::Image.repo.root.to_s
      end
    end
  end
end
