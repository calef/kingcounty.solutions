# frozen_string_literal: true

require 'digest'
require 'fileutils'
require 'mini_magick'
require 'open-uri'
require 'uri'
require_relative '../logging'
require_relative '../support/front_matter_document'
require_relative '../support/http_client'
require_relative '../feed_discovery'

module Mayhem
  module Content
    class ContentImageExtractor
      IMAGE_DOCS_DIR = '_images'
      POSTS_DIR = '_posts'
      EVENTS_DIR = '_events'
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
      RASTER_EXTENSIONS = %w[.jpg .jpeg .png .gif .bmp .tif .tiff].freeze
      MIN_IMAGE_DIMENSION = begin
        Integer(ENV.fetch('IMAGE_MIN_DIMENSION', '300'))
      rescue StandardError
        300
      end

      attr_reader :logger

      def initialize(
        posts_dir: POSTS_DIR,
        events_dir: EVENTS_DIR,
        image_docs_dir: IMAGE_DOCS_DIR,
        asset_dir: IMAGE_ASSET_DIR,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        open_timeout: DEFAULT_OPEN_TIMEOUT,
        read_timeout: DEFAULT_READ_TIMEOUT,
        http_client: nil
      )
        @content_dirs = [posts_dir, events_dir].compact.uniq
        @image_docs_dir = image_docs_dir
        @asset_dir = asset_dir
        @logger = logger
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        FileUtils.mkdir_p(@image_docs_dir)
        FileUtils.mkdir_p(@asset_dir)
        @http = http_client || Mayhem::Support::HttpClient.new(timeout: @read_timeout, logger: @logger)
      end

      def run
        cache = {}
        stats = Hash.new(0)
        @content_dirs.each do |dir|
          Dir.glob(File.join(dir, '*.md')).each do |path|
            process_post(path, cache, stats)
          end
        end
        log_summary(stats)
        stats
      end

      private

      def process_post(path, cache, stats)
        document = Mayhem::Support::FrontMatterDocument.load(path, logger:)
        unless document
          stats[:missing_frontmatter] += 1
          return
        end
        frontmatter = document.front_matter
        handle_unpublished(document, stats) && return if frontmatter['published'] == false

        if frontmatter.key?('images')
          stats[:already_has_images] += 1
          logger.debug "Skipping #{path}: images already present"
          return
        end

        markdown_body = frontmatter['original_markdown_body']
        unless markdown_body
          stats[:missing_original_markdown] += 1
          ensure_empty_images(document, stats)
          return
        end

        images = extract_images(markdown_body)
        if images.empty?
          stats[:no_images_found] += 1
          ensure_empty_images(document, stats)
          return
        end

        collected_ids = download_images(images, cache, frontmatter, stats)
        if collected_ids.empty?
          stats[:no_valid_images] += 1
          ensure_empty_images(document, stats)
          return
        end

        existing_ids = Array(frontmatter['images']).map(&:to_s)
        updated_ids = (existing_ids + collected_ids).uniq
        return if updated_ids == existing_ids

        frontmatter['images'] = updated_ids
        document.save
        stats[:posts_updated] += 1
        logger.info "Updated #{path} with #{collected_ids.length} image IDs"
      end

      def handle_unpublished(document, stats)
        stats[:skipped_unpublished] += 1
        ensure_empty_images(document, stats)
      end

      def ensure_empty_images(document, stats)
        return if document.front_matter['images'].is_a?(Array) && document.front_matter['images'].empty?

        document.front_matter['images'] = []
        document.save
        logger.info "Set empty images list for #{document.path}"
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

      def download_images(images, cache, frontmatter, stats)
        collected_ids = []
        images.each do |img|
          cached_checksum = cache[img[:url]]
          if cached_checksum
            collected_ids << cached_checksum
            next
          end

          downloaded = download_image(img[:url])
          unless downloaded
            stats[:download_failures] += 1
            next
          end

          converted_data, converted_ext = convert_to_webp(downloaded[:data], downloaded[:ext], img[:url])
          next if converted_ext == '.webp' && !meets_minimum_dimensions?(converted_data, img[:url], stats)

          checksum = Digest::SHA256.hexdigest(converted_data)
          filename = image_asset_filename(checksum, converted_ext) { converted_data }
          ensure_image_doc(checksum, img[:alt], filename, frontmatter, img[:url])
          cache[img[:url]] = checksum
          collected_ids << checksum
        end
        collected_ids.uniq
      end

      def download_image(url)
        uri = URI.parse(url)
        return nil unless %w[http https].include?(uri.scheme) && uri.host

        page = @http.fetch(uri.to_s, accept: Mayhem::FeedDiscovery::ACCEPT_FEED, max_bytes: 2_097_152)
        data = page[:body]
        { data:, ext: image_extension(uri, nil) }
      rescue StandardError => e
        logger.warn "Failed to download #{url}: #{e.message}"
        nil
      end

      def image_extension(uri, content_type)
        from_path = File.extname(uri.path).downcase
        return from_path if from_path =~ /\.(jpg|jpeg|png|gif|webp|svg)$/

        case content_type.to_s.split(';').first
        when 'image/jpeg' then '.jpg'
        when 'image/png' then '.png'
        when 'image/gif' then '.gif'
        when 'image/webp' then '.webp'
        when 'image/svg+xml' then '.svg'
        else '.img'
        end
      end

      def convert_to_webp(data, ext, source_url)
        ext = ext.to_s.downcase
        return [data, ext] unless RASTER_EXTENSIONS.include?(ext)

        image = MiniMagick::Image.read(data)
        image.format 'webp'
        [image.to_blob, '.webp']
      rescue StandardError => e
        logger.warn "Failed to convert #{source_url} to WebP: #{e.message}"
        [data, ext]
      end

      def meets_minimum_dimensions?(data, source_url, stats)
        return true unless MIN_IMAGE_DIMENSION.positive?

        image = MiniMagick::Image.read(data)
        if image.width >= MIN_IMAGE_DIMENSION && image.height >= MIN_IMAGE_DIMENSION
          true
        else
          logger.info(
            "Skipping #{source_url}: WebP image " \
            "#{image.width}x#{image.height} smaller than #{MIN_IMAGE_DIMENSION}px"
          )
          stats[:skipped_small_images] += 1
          false
        end
      rescue MiniMagick::Error => e
        logger.warn "Failed to inspect dimensions for #{source_url}: #{e.message}"
        stats[:skipped_small_images] += 1
        false
      end

      def image_asset_filename(checksum, ext)
        filename = "#{checksum}#{ext}"
        path = File.join(@asset_dir, filename)
        File.binwrite(path, yield) unless File.exist?(path)
        filename
      end

      def ensure_image_doc(checksum, alt, filename, frontmatter, original_url)
        doc_path = File.join(@image_docs_dir, "#{checksum}.md")
        return if File.exist?(doc_path)

        frontmatter_data = {
          'checksum' => checksum,
          'image_url' => "/#{@asset_dir}/#{filename}".gsub(%r{//+}, '/'),
          'source_url' => original_url
        }
        title = alt.to_s.strip
        title = 'Image' if title.empty?
        frontmatter_data['title'] = title
        frontmatter_data['source'] = frontmatter['source'] if frontmatter['source']
        frontmatter_data['date'] = frontmatter['date'] if frontmatter['date']

        document = Mayhem::Support::FrontMatterDocument.new(
          path: doc_path,
          front_matter: frontmatter_data,
          body: ''
        )
        document.save
      end

      def log_summary(stats)
        summary_fields = {
          posts_updated: stats[:posts_updated],
          empties_added: stats[:empties_added],
          skipped_unpublished: stats[:skipped_unpublished],
          already_has_images: stats[:already_has_images],
          missing_frontmatter: stats[:missing_frontmatter],
          missing_original_markdown: stats[:missing_original_markdown],
          no_images_found: stats[:no_images_found],
          no_valid_images: stats[:no_valid_images],
          download_failures: stats[:download_failures],
          skipped_small_images: stats[:skipped_small_images]
        }
        summary = summary_fields.map { |k, v| "#{k}=#{v}" }.join(', ')
        logger.info "extract-images-from-content complete: #{summary}"
      end
    end
  end
end
