# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class AbstractJekyllCollection < FMRepo::Record
      class << self
        def collection_dir
          glob = scope_glob
          raise "Missing scope glob for #{name}" if glob.to_s.empty?

          # Expect the scope glob to look like `_collection_name/**/*.{md,markdown}`
          # (or otherwise have the collection root as the first path segment).
          # We strip any leading `./` and then take the first segment as the
          # collection directory under the repo root.
          normalized = glob.to_s.sub(%r{\A\./}, '')
          repo.root.join(normalized.split('/').first).to_s
        end

        private

        def scope_glob
          return config.glob if respond_to?(:config) && config.respond_to?(:glob) && config.glob

          %i[@scope @scope_config @scope_options].each do |ivar|
            next unless instance_variable_defined?(ivar)

            value = instance_variable_get(ivar)
            return value[:glob] || value['glob'] if value.is_a?(Hash)
          end

          nil
        end
      end

      def published
        self['published']
      end

      def published?
        self['published'] != false
      end

      def title
        self['title']
      end
    end
  end
end
