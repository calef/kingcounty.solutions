# frozen_string_literal: true

require 'digest'
require 'tmpdir'
require 'fileutils'
require_relative 'test_helper'
require_relative '../lib/mayhem/logging'
require_relative '../lib/mayhem/content/content_image_extractor'
require_relative '../lib/mayhem/support/front_matter_document'

module News
  class ContentImageExtractorTest < Minitest::Test
    def test_updates_post_with_downloaded_image
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, 'posts')
        images_dir = File.join(dir, 'images')
        assets_dir = File.join(dir, 'assets')
        FileUtils.mkdir_p(posts_dir)
        events_dir = File.join(dir, 'events')
        FileUtils.mkdir_p(events_dir)

        post_path = File.join(posts_dir, 'sample.md')
        File.write(
          post_path,
          <<~MD
            ---
            title: Sample
            source: Example Org
            source_url: https://example.org/post
            original_markdown_body: "![Alt text](https://example.org/image.png)"
            ---
            Body content
          MD
        )

        extractor = Mayhem::Content::ContentImageExtractor.new(
          posts_dir: posts_dir,
          image_docs_dir: images_dir,
          asset_dir: assets_dir,
          events_dir: events_dir,
          logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
        )

        extractor.stub(:download_image, { data: 'image-data', ext: '.png' }) do
          extractor.stub(:convert_to_webp, ['image-data', '.webp']) do
            extractor.stub(:meets_minimum_dimensions?, true) do
              extractor.run
            end
          end
        end

        document = Mayhem::Support::FrontMatterDocument.load(post_path)
        checksums = document.front_matter['images']

        refute_nil checksums
        assert_equal 1, checksums.length

        checksum = Digest::SHA256.hexdigest('image-data')
        image_doc_path = File.join(images_dir, "#{checksum}.md")

        assert_path_exists image_doc_path, 'expected image document to be created'
      end
    end

    def test_processes_events_directory
      Dir.mktmpdir do |dir|
        posts_dir = File.join(dir, 'posts')
        images_dir = File.join(dir, 'images')
        assets_dir = File.join(dir, 'assets')
        events_dir = File.join(dir, 'events')
        FileUtils.mkdir_p(events_dir)

        event_path = File.join(events_dir, 'event.md')
        File.write(
          event_path,
          <<~MD
            ---
            title: Sample Event
            source: Example Org
            source_url: https://example.org/event
            original_markdown_body: "![Event image](https://example.org/event.png)"
            ---
            Event body
          MD
        )

        extractor = Mayhem::Content::ContentImageExtractor.new(
          posts_dir: posts_dir,
          events_dir: events_dir,
          image_docs_dir: images_dir,
          asset_dir: assets_dir,
          logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
        )

        extractor.stub(:download_image, { data: 'image-data', ext: '.png' }) do
          extractor.stub(:convert_to_webp, ['image-data', '.webp']) do
            extractor.stub(:meets_minimum_dimensions?, true) do
              extractor.run
            end
          end
        end

        document = Mayhem::Support::FrontMatterDocument.load(event_path)
        checksums = document.front_matter['images']

        refute_nil checksums
        assert_equal 1, checksums.length
      end
    end
  end
end
