# frozen_string_literal: true

require 'yaml'

module Mayhem
  module News
    class RssImporter
      include Mayhem::Loggable

      class Config
        MAX_ITEM_AGE_DAYS = 365

        def initialize(max_item_age_days:, config_path:)
          @max_item_age_days = max_item_age_days
          @config_path = config_path
        end

        def max_item_age_days
          return @max_item_age_days if @max_item_age_days

          value = read_config(@config_path)
          return value if value.is_a?(Numeric)

          MAX_ITEM_AGE_DAYS
        end

        private

        def read_config(config_path)
          return unless File.exist?(config_path)

          data = YAML.safe_load_file(config_path)
          data && data['rss_max_item_age_days']
        rescue StandardError => e
          logger.warn("Failed to read config #{config_path}: #{e.message}")
          nil
        end
      end
    end
  end
end
