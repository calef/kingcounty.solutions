# frozen_string_literal: true

require 'fileutils'
require 'seldon'

require_relative '../front_matter/document'
require_relative '../models/event'
require_relative '../models/image'
require_relative '../models/news'

# TODO: replace use of Mayhem::FrontMatter::Document with respective Mayhem::Models::* classes

module Mayhem
  module Images
    class Pruner
      include Seldon::Loggable

      attr_reader :posts_dir, :images_dir, :assets_dir

      def initialize(assets_dir:)
        @posts_dir = Mayhem::Models::News.collection_dir
        @images_dir = Mayhem::Models::Image.collection_dir
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

        Dir.glob(File.join(events_dir, '*.md')).each do |path|
          next if excluded_paths.include?(path)

          document = Mayhem::FrontMatter::Document.load(path)
          next unless document

          collect_image_checksums(document.front_matter).each { |id| counts[id] += 1 }
        end

        counts
      end

      def prune(image_checksums, excluded_paths: Set.new, excluded_events: nil)
        excluded_paths = normalize_excluded_paths(excluded_paths, excluded_events)
        remaining_refs = remaining_image_counts(excluded_paths)
        prune_images(image_checksums, remaining_refs)
      end

      private

      def normalize_excluded_paths(excluded_paths, excluded_events)
        paths = Set.new(Array(excluded_paths).compact)
        Array(excluded_events).each do |event|
          next unless event

          path = event_path_for(event)
          paths << path unless path.empty?
        end
        paths
      end

      def event_path_for(event)
        path = event.path.to_s
        path = event.id.to_s if path.empty? && event.respond_to?(:id)
        return '' if path.empty?

        root = File.expand_path('..', events_dir.to_s)
        File.absolute_path(path, root)
      end

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

      def events_dir
        Mayhem::Models::Event.collection_dir
      end
    end
  end
end
