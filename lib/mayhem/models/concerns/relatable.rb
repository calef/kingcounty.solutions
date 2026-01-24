# frozen_string_literal: true

module Mayhem
  module Models
    module Concerns
      # Provides a helper for finding related records across models.
      #
      # Usage:
      #   class Topic < AbstractJekyllCollection
      #     include Mayhem::Models::Concerns::Relatable
      #
      #     def news
      #       find_related_records(News, match_key: :title, target_field: :topic_titles)
      #     end
      #   end
      module Relatable
        private

        # Find records from another model that reference this record.
        #
        # @param model [Class] The model class to search (e.g., News, Event)
        # @param match_key [Symbol] The method on self to get the value to match (:title or :checksum)
        # @param target_field [Symbol] The method on target records to check for the match
        # @param array_field [Boolean] Whether target_field returns an array (default: true)
        # @return [Array] Matching records, or empty array if match_key value is blank
        def find_related_records(model, match_key:, target_field:, array_field: true)
          match_value = send(match_key).to_s.strip
          return [] if match_value.empty?

          model.all.select do |record|
            if array_field
              Array(record.send(target_field)).map(&:to_s).map(&:strip).include?(match_value)
            else
              record.send(target_field) == match_value
            end
          end
        end
      end
    end
  end
end
