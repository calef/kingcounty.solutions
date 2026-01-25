# frozen_string_literal: true

require_relative 'abstract_jekyll_collection'
require_relative 'concerns/located'
require_relative 'concerns/sourced'
require_relative 'concerns/topical'

module Mayhem
  module Models
    class AbstractContent < AbstractJekyllCollection
      include Mayhem::Models::Concerns::Located
      include Mayhem::Models::Concerns::Sourced
      include Mayhem::Models::Concerns::Topical

      fm_accessor :feed_content, :feed_content_checksum, :original_source_html
      fm_accessor :image_checksums, default: []
      fm_boolean :locked
      fm_boolean :summarized

      # Returns Image records for each checksum in image_checksums.
      # Images that cannot be found are excluded from the result.
      def images
        require_relative 'image'

        image_checksums.filter_map do |checksum|
          Image.find_by(checksum:)
        end
      end
    end
  end
end
