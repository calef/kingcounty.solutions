# frozen_string_literal: true

require 'nokogiri'

module Mayhem
  module News
    class RssImporter
      class FeedSanitizer
        def initialize(logger:)
          @logger = logger
        end

        def sanitize(xml, source_title, rss_url)
          return xml unless xml

          doc = Nokogiri::XML(xml) { |config| config.nonet.recover }
          return xml unless doc

          declared_prefixes = doc.collect_namespaces.keys.map do |name|
            name.split(':', 2).last
          end.compact.to_set
          removed_nodes = false

          doc.traverse do |node|
            next unless node.element?

            if undeclared_prefix?(node, declared_prefixes)
              node.remove
              removed_nodes = true
              next
            end

            node.attribute_nodes.each do |attr|
              next unless undeclared_prefix?(attr, declared_prefixes)

              attr.remove
              removed_nodes = true
            end
          end

          @logger.info "Sanitized namespaced XML for '#{source_title}' (#{rss_url}) due to undeclared prefixes" if removed_nodes
          remove_duplicate_xml_declaration(doc)
          doc.to_xml
        rescue StandardError => e
          @logger.warn "Failed to sanitize feed XML for '#{source_title}' (#{rss_url}): #{e.message}"
          xml
        end

        private

        def undeclared_prefix?(node_or_attr, declared_prefixes)
          ns = node_or_attr.namespace
          return false if ns

          name = node_or_attr.name
          return false unless name&.include?(':')

          prefix = name.split(':', 2).first
          return false if declared_prefixes.include?(prefix)

          true
        end

        def remove_duplicate_xml_declaration(doc)
          doc.children.each do |child|
            next unless child.processing_instruction?
            next unless child.name.to_s.casecmp('xml').zero?

            child.remove
          end
        end
      end
    end
  end
end
