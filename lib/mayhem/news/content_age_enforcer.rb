# frozen_string_literal: true

require 'fileutils'
require 'set'
require 'time'
require 'yaml'

require_relative '../logging'
require_relative '../support/front_matter_document'

module Mayhem
  module News
    class ContentAgeEnforcer
      POSTS_DIR = '_posts'
      IMAGES_DIR = '_images'
      IMAGE_ASSETS_DIR = File.join('assets', 'images')
      DEFAULT_MAX_AGE_DAYS = 365
      CONFIG_PATH = File.expand_path('../../../_config.yml', __dir__)

      def initialize(
        posts_dir: POSTS_DIR,
        images_dir: IMAGES_DIR,
        assets_dir: IMAGE_ASSETS_DIR,
        config_path: CONFIG_PATH,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        clock: -> { Time.now }
      )
        @posts_dir = posts_dir
        @images_dir = images_dir
        @assets_dir = assets_dir
        @config_path = config_path
        @logger = logger
        @clock = clock
      end

      def run
        max_age_days = determine_max_age_days
        cutoff = @clock.call - (max_age_days * 24 * 60 * 60)
        posts = posts_older_than(cutoff)
        if posts.empty?
          @logger.info "No posts older than #{max_age_days} days were found."
          return
        end

        excluded_paths = posts.map { |entry| entry[:path] }.to_set
        remaining_image_refs = remaining_image_counts(excluded_paths)

        posts.each do |entry|
          @logger.info "Removing post #{File.basename(entry[:path])}"
          remove_file(entry[:path])
        end

        removed_images = cleanup_images(posts.flat_map { |entry| entry[:images] }.uniq, remaining_image_refs)

        @logger.info "Removed #{posts.size} post#{posts.size == 1 ? '' : 's'} older than #{max_age_days} days."
        @logger.info "Removed #{removed_images.size} image metadata entr#{removed_images.size == 1 ? 'y' : 'ies'}."
      end

      private

      def determine_max_age_days
        value = read_config_value
        return value if value&.positive?

        DEFAULT_MAX_AGE_DAYS
      end

      def read_config_value
        return unless File.exist?(@config_path)

        config = YAML.safe_load(File.read(@config_path))
        number = config && config['content_max_age_days']
        Integer(number) if number
      rescue StandardError => e
        @logger.warn "Failed to read content_max_age_days from #{@config_path}: #{e.message}"
        nil
      end

      def posts_older_than(cutoff)
        Dir.glob(File.join(@posts_dir, '*.md')).each_with_object([]) do |path, memo|
          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          published_at = parse_date(document.front_matter['date'])
          next unless published_at
          next unless published_at < cutoff

          memo << { path: path, images: collect_image_ids(document.front_matter) }
        end
      end

      def parse_date(value)
        return value if value.is_a?(Time)
        return value.to_time if value.respond_to?(:to_time)

        Time.parse(value.to_s)
      rescue StandardError
        nil
      end

      def collect_image_ids(front_matter)
        Array(front_matter['images']).map(&:to_s).map(&:strip).reject(&:empty?)
      end

      def remaining_image_counts(excluded_paths)
        counts = Hash.new(0)
        Dir.glob(File.join(@posts_dir, '*.md')).each do |path|
          next if excluded_paths.include?(path)

          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          collect_image_ids(document.front_matter).each { |id| counts[id] += 1 }
        end
        counts
      end

      def cleanup_images(image_ids, remaining_refs)
        removed = []
        image_ids.each do |id|
          next if remaining_refs[id] && remaining_refs[id] > 0

          removed << id
          remove_file(File.join(@images_dir, "#{id}.md"))
          Dir.glob(File.join(@assets_dir, "#{id}.*")).each { |asset| remove_file(asset) }
        end
        removed
      end

      def remove_file(path)
        FileUtils.rm(path)
      rescue Errno::ENOENT
        # already removed
      end
    end
  end
end
