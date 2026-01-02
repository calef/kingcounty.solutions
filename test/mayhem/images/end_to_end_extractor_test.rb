# frozen_string_literal: true

require 'digest'
require 'tmpdir'
require 'fileutils'
require 'seldon'

require_relative '../../test_helper'
require_relative '../../../lib/mayhem/images/extractor'
require_relative '../../../lib/mayhem/image_files/downloader'
require_relative '../../../lib/mayhem/image_files/converter'
require_relative '../../../lib/mayhem/image_files/validator'
require_relative '../../../lib/mayhem/front_matter/document'

# TODO: change from using mayhem/front_matter/document to using the appropriate Mayhem::Models classes instead.

module News
  class ImageExtractorEndToEndTest < Minitest::Test
    private

    def stub_image_processing(extractor)
      # Stub the downloader, converter, and validator instances
      downloader_stub = Minitest::Mock.new
      downloader_stub.expect(:download, { data: 'image-data', ext: '.png' }) do |url, stats|
        url.is_a?(String) && stats.is_a?(Hash)
      end

      converter_stub = Minitest::Mock.new
      converter_stub.expect(:convert_to_webp, ['image-data', '.webp']) do |data, ext, url|
        data.is_a?(String) && ext.is_a?(String) && url.is_a?(String)
      end

      validator_stub = Minitest::Mock.new
      validator_stub.expect(:meets_minimum_dimensions?, true) do |data, url, stats|
        data.is_a?(String) && url.is_a?(String) && stats.is_a?(Hash)
      end

      extractor.instance_variable_set(:@downloader, downloader_stub)
      extractor.instance_variable_set(:@converter, converter_stub)
      extractor.instance_variable_set(:@validator, validator_stub)

      [downloader_stub, converter_stub, validator_stub]
    end

    public

  def test_updates_post_with_downloaded_image
      FMRepo::TestHelpers.with_temp_repo(role: :news) do
        FMRepo::TestHelpers.with_temp_repo(role: :events) do
          Dir.mktmpdir do |dir|
            posts_dir = Mayhem::Models::News.collection_dir
            images_dir = File.join(dir, 'images')
            assets_dir = File.join(dir, 'assets')
            FileUtils.mkdir_p(posts_dir)

            post_path = File.join(posts_dir, 'sample.md')
            File.write(
              post_path,
              <<~MD
                ---
                title: Sample
                source: Example Org
                source_url: https://example.org/post
                summarized: true
                original_source_html: "![Alt text](https://example.org/image.png)"
                ---
                Body content
              MD
            )

            extractor = Mayhem::Images::Extractor.new(
              image_docs_dir: images_dir,
              asset_dir: assets_dir
            )

            stubs = stub_image_processing(extractor)
            extractor.run

            document = Mayhem::FrontMatter::Document.load(post_path)
            checksums = document.front_matter['image_checksums']

            refute_nil checksums
            assert_equal 1, checksums.length

            checksum = Digest::SHA256.hexdigest('image-data')
            image_doc_path = File.join(images_dir, "#{checksum}.md")

            assert_path_exists image_doc_path, 'expected image document to be created'

            stubs.each(&:verify)
          end
        end
      end
  end

  def test_processes_events_directory
      FMRepo::TestHelpers.with_temp_repo(role: :news) do
        FMRepo::TestHelpers.with_temp_repo(role: :events) do
          Dir.mktmpdir do |dir|
            posts_dir = Mayhem::Models::News.collection_dir
            images_dir = File.join(dir, 'images')
            assets_dir = File.join(dir, 'assets')
            events_dir = Mayhem::Models::Event.collection_dir
            FileUtils.mkdir_p(posts_dir)
            FileUtils.mkdir_p(events_dir)

            event_path = File.join(events_dir, 'event.md')
            File.write(
              event_path,
              <<~MD
                ---
                title: Sample Event
                organization_title: Example Org
                source_url: https://example.org/event
                summarized: true
                original_source_html: "![Event image](https://example.org/event.png)"
                ---
                Event body
              MD
            )

            extractor = Mayhem::Images::Extractor.new(
              image_docs_dir: images_dir,
              asset_dir: assets_dir
            )

            stubs = stub_image_processing(extractor)
            extractor.run

            document = Mayhem::FrontMatter::Document.load(event_path)
            checksums = document.front_matter['image_checksums']

            refute_nil checksums
            assert_equal 1, checksums.length

            stubs.each(&:verify)
          end
        end
      end
  end

  def test_skips_locked_entries
      FMRepo::TestHelpers.with_temp_repo(role: :news) do
        FMRepo::TestHelpers.with_temp_repo(role: :events) do
          Dir.mktmpdir do |dir|
            posts_dir = Mayhem::Models::News.collection_dir
            images_dir = File.join(dir, 'images')
            assets_dir = File.join(dir, 'assets')
            FileUtils.mkdir_p(posts_dir)

            post_path = File.join(posts_dir, 'locked.md')
            File.write(
              post_path,
              <<~MD
                ---
                title: Locked Post
                source: Example Org
                source_url: https://example.org/post
                original_source_html: "![Alt](https://example.org/image.png)"
                locked: true
                ---
                Body
              MD
            )

            extractor = Mayhem::Images::Extractor.new(
              image_docs_dir: images_dir,
              asset_dir: assets_dir
            )

            extractor.run

            document = Mayhem::FrontMatter::Document.load(post_path)
            assert_nil document.front_matter['image_checksums']
          end
        end
      end
  end
  end
end
