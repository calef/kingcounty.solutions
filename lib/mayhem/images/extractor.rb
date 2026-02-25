# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'mini_magick'
require 'seldon'
require 'time'
require 'uri'
require_relative '../feed/discovery'
require_relative '../image_files/validator'
require_relative '../image_files/converter'
require_relative '../image_files/downloader'
require_relative '../image_files/writer'
require_relative '../models/event'
require_relative '../models/image'
require_relative '../models/news'

module Mayhem
  module Images
    class Extractor
      include Seldon::Loggable

      IMAGE_ASSET_DIR = File.join('assets', 'images')
      DEFAULT_OPEN_TIMEOUT = begin
        Integer(ENV.fetch('IMAGE_OPEN_TIMEOUT', '10'))
      rescue StandardError
        10
      end
      DEFAULT_READ_TIMEOUT = begin
        Integer(ENV.fetch('IMAGE_READ_TIMEOUT', '30'))
      rescue StandardError
        30
      end
      MIN_IMAGE_DIMENSION = begin
        Integer(ENV.fetch('IMAGE_MIN_DIMENSION', '300'))
      rescue StandardError
        300
      end

      def initialize(
        asset_dir: IMAGE_ASSET_DIR,
        open_timeout: DEFAULT_OPEN_TIMEOUT,
        read_timeout: DEFAULT_READ_TIMEOUT,
        min_dimension: MIN_IMAGE_DIMENSION,
        http_client: nil
      )
        @asset_dir = asset_dir
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @min_dimension = min_dimension
        @http = http_client || Seldon::Support::HttpClient.new(
          timeout: @read_timeout,
          cookie_jar: Seldon::Support::CookieJar.new
        )

        @validator = Mayhem::ImageFiles::Validator.new(min_dimension: @min_dimension)
        @converter = Mayhem::ImageFiles::Converter.new
        @downloader = Mayhem::ImageFiles::Downloader.new(http_client: @http, validator: @validator)
        @writer = Mayhem::ImageFiles::Writer.new(asset_dir: @asset_dir)
      end

      def run
        cache = {}
        stats = Hash.new(0)
        Mayhem::Models::News.all.each { |record| process_record(record, cache, stats) }
        Mayhem::Models::Event.all.each { |record| process_record(record, cache, stats) }
        log_summary(stats)
        stats
      end

      private

      def process_record(record, cache, stats)
        record_id = record.id

        if record.locked? == true
          stats[:skipped_locked] += 1
          logger.debug "Skipping #{record_id}: locked is true"
          return
        end
        handle_unpublished(record, stats) && return unless record.published?

        unless record.summarized? == true
          stats[:skipped_unsummarized] += 1
          logger.debug "Skipping #{record_id}: summarized is not true"
          return
        end

        if record.images_extracted? == true
          stats[:already_has_images] += 1
          logger.debug "Skipping #{record_id}: images already extracted"
          return
        end

        source_html = record.original_source_html || record.feed_content
        unless source_html
          stats[:missing_source_html] += 1
          ensure_empty_image_checksums(record, stats)
          return
        end

        images = extract_images(source_html)
        if images.empty?
          stats[:no_images_found] += 1
          ensure_empty_image_checksums(record, stats)
          return
        end

        collected_ids = download_images(images, cache, record, stats)
        if collected_ids.empty?
          stats[:no_valid_images] += 1
          ensure_empty_image_checksums(record, stats)
          return
        end

        existing_ids = record.image_checksums.map(&:to_s)
        updated_ids = (existing_ids + collected_ids).uniq
        return if updated_ids == existing_ids

        record.image_checksums = updated_ids
        record.images_extracted = true
        record.save!
        stats[:posts_updated] += 1
        logger.info "Updated #{record_id} with #{collected_ids.length} image IDs"
      end

      def handle_unpublished(record, stats)
        stats[:skipped_unpublished] += 1
        ensure_empty_image_checksums(record, stats)
      end

      def ensure_empty_image_checksums(record, stats)
        return if record.images_extracted? == true

        record.image_checksums = []
        record.images_extracted = true
        record.save!
        record_id = record.id
        logger.info "Set empty image_checksums list for #{record_id}"
        stats[:empties_added] += 1
      end

      def extract_images(markdown)
        results = []
        markdown.to_s.scan(/!\[(.*?)\]\((\S+?)(?:\s+"[^"]*")?\)/m) do |alt, url|
          results << { alt: alt.to_s.strip, url: url.to_s.strip }
        end
        markdown.to_s.scan(/<img[^>]*>/i) do |tag|
          src = tag[/\bsrc\s*=\s*["']([^"']+)["']/i, 1]
          next unless src

          alt = tag[/\balt\s*=\s*["']([^"']*)["']/i, 1]
          results << { alt: alt.to_s.strip, url: src.strip }
        end
        results.reject { |img| img[:url].nil? || img[:url].empty? }
      end

      def download_images(images, cache, record, stats)
        collected_ids = []
        images.each do |img|
          cached_checksum = cache[img[:url]]
          if cached_checksum
            collected_ids << cached_checksum
            next
          end
          downloaded = @downloader.download(img[:url], stats)
          next unless downloaded

          converted_data, converted_ext, converted = @converter.convert_to_webp(downloaded[:data], downloaded[:ext], img[:url])
          if converted && converted_data.nil?
            stats[:conversion_failures] += 1
            next
          end
          next if converted_ext == '.webp' && !@validator.meets_minimum_dimensions?(converted_data, img[:url], stats)

          checksum = Digest::SHA256.hexdigest(converted_data)
          filename = @writer.write(checksum, converted_ext, converted_data)
          ensure_image_record(checksum, img[:alt], filename, record, img[:url])
          cache[img[:url]] = checksum
          collected_ids << checksum
        end
        collected_ids.uniq
      end

      def ensure_image_record(checksum, alt, filename, source_record, original_url)
        # Check if image record already exists
        existing = Mayhem::Models::Image.find_by(checksum: checksum)
        return if existing

        title = alt.to_s.strip
        title = 'Image' if title.empty?
        organization_title = source_record.respond_to?(:organization_title) ? source_record.organization_title : source_record['organization_title']

        front_matter = {
          'checksum' => checksum,
          'image_url' => "/#{@asset_dir}/#{filename}".gsub(%r{//+}, '/'),
          'source_url' => original_url,
          'title' => title,
          'date' => resolve_date(source_record)
        }
        front_matter['alt_text'] = alt.to_s.strip unless alt.to_s.strip.empty?
        front_matter['organization_title'] = organization_title unless organization_title.to_s.strip.empty?

        Mayhem::Models::Image.create!(front_matter, body: '')
      end

      def log_summary(stats)
        summary_fields = {
          posts_updated: stats[:posts_updated],
          empties_added: stats[:empties_added],
          skipped_unpublished: stats[:skipped_unpublished],
          skipped_locked: stats[:skipped_locked],
          skipped_unsummarized: stats[:skipped_unsummarized],
          already_has_images: stats[:already_has_images],
          missing_source_html: stats[:missing_source_html],
          no_images_found: stats[:no_images_found],
          no_valid_images: stats[:no_valid_images],
          download_failures: stats[:download_failures],
          conversion_failures: stats[:conversion_failures],
          skipped_unsupported_images: stats[:skipped_unsupported_images],
          skipped_small_images: stats[:skipped_small_images]
        }
        summary = summary_fields.map { |k, v| "#{k}=#{v}" }.join(', ')
        logger.info "extract-images-from-content complete: #{summary}"
      end

      def resolve_date(record)
        candidate = record['date'] || record['start_date']
        if candidate
          normalize_date(candidate)
        else
          fallback = Time.now.utc.iso8601
          logger.warn "Missing date for image metadata; using #{fallback}"
          fallback
        end
      end

      def normalize_date(value)
        Time.iso8601(value.to_s).iso8601
      rescue ArgumentError
        Time.parse(value.to_s).iso8601
      rescue StandardError => e
        fallback = Time.now.utc.iso8601
        logger.warn "Invalid date #{value.inspect} (#{e.message}); using #{fallback}"
        fallback
      end
    end
  end
end
