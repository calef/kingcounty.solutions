# frozen_string_literal: true

require 'fileutils'

require_relative '../front_matter/document'
require_relative '../logging'

# TODO: replace use of Mayhem::FrontMatter::Document with respective Mayhem::Models::* classes

module Mayhem
  module Images
    class Pruner
      include Mayhem::Loggable

      attr_reader :posts_dir, :events_dir, :images_dir, :assets_dir

      def initialize(posts_dir:, images_dir:, assets_dir:, events_dir: nil)
        @posts_dir = posts_dir
        @events_dir = events_dir
        @images_dir = images_dir
        @assets_dir = assets_dir
      end

      def collect_image_checksums(front_matter)
        Array(front_matter['image_checksums']).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def remaining_image_counts(excluded_paths = Set.new)
        counts = Hash.new(0)

        Dir.glob(File.join(@posts_dir, '*.md')).each do |path|
          next if excluded_paths.include?(path)

          document = Mayhem::FrontMatter::Document.load(path)
          next unless document

          collect_image_checksums(document.front_matter).each { |id| counts[id] += 1 }
        end

        if @events_dir
          Dir.glob(File.join(@events_dir, '*.md')).each do |path|
            next if excluded_paths.include?(path)

            document = Mayhem::FrontMatter::Document.load(path)
            next unless document

            collect_image_checksums(document.front_matter).each { |id| counts[id] += 1 }
          end
        end

        counts
      end

      def prune(image_checksums, excluded_paths: Set.new)
        remaining_refs = remaining_image_counts(excluded_paths)
        prune_images(image_checksums, remaining_refs)
      end

      private

      def prune_images(image_checksums, remaining_refs)
        removed = []
        image_checksums.each do |id|
          next if remaining_refs[id]&.positive?

          removed << id
          delete_image_files(id)
        end
        removed
      end

      def delete_image_files(image_id)
        delete_file(File.join(@images_dir, "#{image_id}.md"))
        Dir.glob(File.join(@assets_dir, "#{image_id}.*")).each { |asset| delete_file(asset) }
      end

      def delete_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end
    end
  end
end
