# frozen_string_literal: true

require 'fmrepo'

module Mayhem
  module Models
    class AbstractJekyllCollection < FMRepo::Record
      class << self
        def collection_dir
          glob = scope_glob
          raise "Missing scope glob for #{name}" if glob.to_s.empty?

          # Expect the scope glob to look like `_collection_name/**/*.md`
          # (or otherwise have the collection root as the first path segment).
          # We strip any leading `./` and then take the first segment as the
          # collection directory under the repo root.
          normalized = glob.to_s.sub(%r{\A\./}, '')
          repo.root.join(normalized.split('/').first).to_s
        end

        private

        # Retrieves the glob pattern from FMRepo's scope configuration.
        #
        # Uses the public `scope_config` API provided by FMRepo::Record (v0.2.10+)
        # to access the glob pattern configured via the `scope` class method.
        #
        # @return [String, nil] the glob pattern if configured, otherwise nil
        def scope_glob
          scope_config&.dig(:glob)
        end
      end

      def published
        self['published']
      end

      def published=(value)
        self['published'] = value
      end

      def published?
        self['published'] != false
      end

      def title
        self['title']
      end

      def title=(value)
        self['title'] = value
      end
    end
  end
end
