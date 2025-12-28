# frozen_string_literal: true

module Mayhem
  module News
    class RssImporter
      class SourceEnumerator
        def initialize(organization_model:, sources_dir:)
          @organization_model = organization_model
          @sources_dir = sources_dir
        end

        def records
          records = @organization_model.all.to_a
          return records if @sources_dir.to_s.strip.empty?

          pattern = File.join(File.expand_path(@sources_dir), '*.md')
          records.select do |record|
            path = record.path.to_s
            File.fnmatch?(pattern, path)
          end
        end
      end
    end
  end
end
