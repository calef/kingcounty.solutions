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
require_relative '../../../lib/mayhem/models/event'
require_relative '../../../lib/mayhem/models/image'
require_relative '../../../lib/mayhem/models/news'

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
      converter_stub.expect(:convert_to_webp, ['image-data', '.webp', false]) do |data, ext, url|
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
          FMRepo::TestHelpers.with_temp_repo(role: :images) do
            assets_dir = File.join(Mayhem::Models::Image.repo.root.to_s, 'assets', 'images')
            FileUtils.mkdir_p(assets_dir)

            # Create a post using Models
            post = Mayhem::Models::News.create!(
              {
                'title' => 'Sample',
                'source' => 'Example Org',
                'source_url' => 'https://example.org/post',
                'summarized' => true,
                'original_source_html' => '![Alt text](https://example.org/image.png)'
              },
              body: 'Body content'
            )
            post_id = post.id

            extractor = Mayhem::Images::Extractor.new(
              asset_dir: assets_dir
            )

            stubs = stub_image_processing(extractor)
            extractor.run

            updated_post = Mayhem::Models::News.find(post_id)
            checksums = updated_post['image_checksums']

            refute_nil checksums
            assert_equal 1, checksums.length

            checksum = Digest::SHA256.hexdigest('image-data')
            image = Mayhem::Models::Image.find_by(checksum: checksum)

            refute_nil image, 'expected image record to be created'

            stubs.each(&:verify)
          end
        end
      end
    end

    def test_processes_events_directory
      FMRepo::TestHelpers.with_temp_repo(role: :news) do
        FMRepo::TestHelpers.with_temp_repo(role: :events) do
          FMRepo::TestHelpers.with_temp_repo(role: :images) do
            assets_dir = File.join(Mayhem::Models::Image.repo.root.to_s, 'assets', 'images')
            FileUtils.mkdir_p(assets_dir)

            # Create an event using Models
            event = Mayhem::Models::Event.create!(
              {
                'title' => 'Sample Event',
                'organization_title' => 'Example Org',
                'source_url' => 'https://example.org/event',
                'start_date' => Time.now.utc.iso8601,
                'summarized' => true,
                'original_source_html' => '![Event image](https://example.org/event.png)'
              },
              body: 'Event body'
            )
            event_id = event.id

            extractor = Mayhem::Images::Extractor.new(
              asset_dir: assets_dir
            )

            stubs = stub_image_processing(extractor)
            extractor.run

            updated_event = Mayhem::Models::Event.find(event_id)
            checksums = updated_event['image_checksums']

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
          FMRepo::TestHelpers.with_temp_repo(role: :images) do
            assets_dir = File.join(Mayhem::Models::Image.repo.root.to_s, 'assets', 'images')
            FileUtils.mkdir_p(assets_dir)

            # Create a locked post using Models
            post = Mayhem::Models::News.create!(
              {
                'title' => 'Locked Post',
                'source' => 'Example Org',
                'source_url' => 'https://example.org/post',
                'original_source_html' => '![Alt](https://example.org/image.png)',
                'locked' => true
              },
              body: 'Body'
            )
            post_id = post.id

            extractor = Mayhem::Images::Extractor.new(
              asset_dir: assets_dir
            )

            extractor.run

            updated_post = Mayhem::Models::News.find(post_id)
            assert_nil updated_post['image_checksums']
          end
        end
      end
    end
  end
end
