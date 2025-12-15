# frozen_string_literal: true

require 'fileutils'

require_relative '../front_matter/document'
require_relative '../news/repository'
require_relative '../events/repository'
require_relative 'repository'

module Mayhem
  module Images
    class Pruner
      attr_reader :news_dir, :events_dir, :images_dir, :assets_dir

      def initialize(assets_dir:, logger:, news_dir: nil, images_dir: nil, events_dir: nil, news_repository: nil, events_repository: nil,
                     images_repository: nil)
        @news_dir = news_dir
        @events_dir = events_dir
        @images_dir = images_dir
        @assets_dir = assets_dir
        @logger = logger
        @news_repository = news_repository || Mayhem::News::Repository.new(
          directory: @news_dir || Mayhem::News::Repository::DEFAULT_DIR,
          logger: @logger
        )
        @events_repository = events_repository || (@events_dir ? Mayhem::Events::Repository.new(directory: @events_dir, logger: @logger) : nil)
        @images_repository = images_repository || Mayhem::Images::Repository.new(
          directory: @images_dir || Mayhem::Images::Repository::DEFAULT_DIR,
          logger: @logger
        )
      end

      def collect_image_ids(front_matter)
        Array(front_matter['images']).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def remaining_image_counts(excluded_paths = Set.new)
        counts = Hash.new(0)

        @news_repository.each do |document, path|
          next if excluded_paths.include?(path)

          collect_image_ids(document.front_matter).each { |id| counts[id] += 1 }
        end

        @events_repository&.each do |document, path|
          next if excluded_paths.include?(path)

          collect_image_ids(document.front_matter).each { |id| counts[id] += 1 }
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
        delete_file(@images_repository.path_for(image_id))
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
