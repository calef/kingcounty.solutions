# frozen_string_literal: true

require 'fileutils'

module Mayhem
  module ImageFiles
    class Writer
      attr_reader :asset_dir

      def initialize(asset_dir:)
        @asset_dir = asset_dir
        FileUtils.mkdir_p(@asset_dir)
      end

      def write(checksum, ext, data)
        filename = "#{checksum}#{ext}"
        path = File.join(asset_dir, filename)
        File.binwrite(path, data) unless File.exist?(path)
        filename
      end
    end
  end
end
