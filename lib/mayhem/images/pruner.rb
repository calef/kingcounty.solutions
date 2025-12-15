# frozen_string_literal: true

require 'fileutils'

require_relative '../front_matter/document'
require_relative '../news/repository'
require_relative '../events/repository'
require_relative './repository'

module Mayhem
  module Images
    class Pruner
      attr_reader :posts_dir, :events_dir, :images_dir, :assets_dir

      def initialize(posts_dir: nil, images_dir: nil, assets_dir:, logger:, events_dir: nil, posts_repository: nil, events_repository: nil, images_repository: nil)
        @posts_dir = posts_dir
        @events_dir = events_dir
        @images_dir = images_dir
        @assets_dir = assets_dir
        @logger = logger
        @posts_repository = posts_repository || Mayhem::News::Repository.new(directory: @posts_dir || Mayhem::News::Repository::DEFAULT_DIR)
        @events_repository = events_repository || (@events_dir ? Mayhem::Events::Repository.new(directory: @events_dir) : nil)
        @images_repository = images_repository || Mayhem::Images::Repository.new(directory: @images_dir || Mayhem::Images::Repository::DEFAULT_DIR)
      end

      def collect_image_ids(front_matter)
        Array(front_matter['images']).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def remaining_image_counts(excluded_paths = Set.new)
        counts = Hash.new(0)

        @posts_repository.all_file_paths.each do |path|
          next if excluded_paths.include?(path)

          document = Mayhem::FrontMatter::Document.load(path, logger: @logger)
          next unless document

          collect_image_ids(document.front_matter).each { |id| counts[id] += 1 }
        end

        if @events_repository
          @events_repository.all_file_paths.each do |path|
            next if excluded_paths.include?(path)

            document = Mayhem::FrontMatter::Document.load(path, logger: @logger)
            next unless document

            collect_image_ids(document.front_matter).each { |id| counts[id] += 1 }
          end
        end

        counts
      end

      def prune(image_ids, excluded_paths: Set.new)
        remaining_refs = remaining_image_counts(excluded_paths)
        prune_images(image_ids, remaining_refs)
      end

      private

      def prune_images(image_ids, remaining_refs)
        removed = []
        image_ids.each do |id|
          next if remaining_refs[id]&.positive?

          removed << id
          delete_image_files(id)
        end
        removed
      end

      def delete_image_files(image_id)
        delete_file(@images_repository.file_path(image_id))
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
