# frozen_string_literal: true

require_relative '../../test_helper'
require 'tmpdir'
require 'fileutils'
require 'minitest/autorun'
require_relative '../../../lib/mayhem/image_files/writer'

class ImageFilesWriterTest < Minitest::Test
  def setup
    @tmp_dir = Dir.mktmpdir('assets')
    @writer = Mayhem::ImageFiles::Writer.new(asset_dir: @tmp_dir)
  end

  def teardown
    FileUtils.remove_entry(@tmp_dir)
  end

  def test_write_creates_file_with_checksum_and_extension
    filename = @writer.write('abc123', '.webp', 'image-data')
    assert_equal 'abc123.webp', filename
    assert File.exist?(File.join(@tmp_dir, filename))
  end

  def test_write_saves_data_to_file
    @writer.write('checksum', '.jpg', 'test-data')
    content = File.read(File.join(@tmp_dir, 'checksum.jpg'))
    assert_equal 'test-data', content
  end

  def test_write_does_not_overwrite_existing_file
    @writer.write('same', '.png', 'first-data')
    @writer.write('same', '.png', 'second-data')
    
    content = File.read(File.join(@tmp_dir, 'same.png'))
    assert_equal 'first-data', content
  end

  def test_write_creates_asset_directory_if_not_exists
    new_dir = File.join(@tmp_dir, 'nested', 'deep')
    writer = Mayhem::ImageFiles::Writer.new(asset_dir: new_dir)
    
    writer.write('test', '.gif', 'data')
    assert File.exist?(File.join(new_dir, 'test.gif'))
    
    FileUtils.remove_entry(File.join(@tmp_dir, 'nested'))
  end

  def test_write_handles_binary_data
    binary_data = "\x89PNG\r\n\x1a\n".b
    @writer.write('binary', '.png', binary_data)
    
    content = File.binread(File.join(@tmp_dir, 'binary.png'))
    assert_equal binary_data, content
  end
end
