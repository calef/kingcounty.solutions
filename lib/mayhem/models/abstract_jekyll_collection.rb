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

        # Retrieves the glob pattern from FMRepo's scope configuration.
        #
        # This method uses introspection to access FMRepo's internal implementation
        # details, specifically the instance variables used to store scope configuration.
        # This approach is fragile and depends on FMRepo's internal structure remaining
        # consistent across versions.
        #
        # @return [String, nil] the glob pattern if found, otherwise nil
        #
        # @note **Dependency on FMRepo internals:**
        #   This method directly accesses private instance variables that are set by
        #   FMRepo::Record when the `scope` class method is called. These variables are:
        #   - `@scope` - the primary scope configuration hash
        #   - `@scope_config` - alternative scope configuration storage
        #   - `@scope_options` - another potential scope storage location
        #
        #   These variable names and structure are not part of FMRepo's public API
        #   and may change in future versions without notice, potentially breaking
        #   this implementation.
        #
        # @note **Risk:**
        #   If FMRepo changes its internal scope storage mechanism, this method may:
        #   - Return nil unexpectedly
        #   - Fail to find the glob pattern
        #   - Cause collection_dir to raise an error
        #
        # @see https://github.com/calef/fmrepo FMRepo gem repository (no public documentation exists for the internal scope storage mechanism)
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
