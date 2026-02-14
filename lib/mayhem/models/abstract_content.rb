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

      attribute :feed_content, :feed_content_checksum, :original_source_html
      attribute :image_checksums, default: []
      boolean_attribute :classified
      boolean_attribute :images_extracted
      boolean_attribute :locked
      boolean_attribute :summarized

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
