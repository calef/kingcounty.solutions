# frozen_string_literal: true

require_relative '../logging'
require_relative '../openai/chat_client'
require_relative '../support/front_matter_document'

module Mayhem
  module Content
    # Uses an OpenAI chat model to rewrite Markdown bodies so that they follow
    # AP style. Front matter is left untouched; only the body text is replaced.
    class ApStyleRewriter
      DEFAULT_MODEL = ENV.fetch('OPENAI_AP_STYLE_MODEL', 'gpt-4o-mini')

      attr_reader :logger

      def initialize(
        paths:,
        model: DEFAULT_MODEL,
        dry_run: false,
        chat_client: nil,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @paths = Array(paths).flatten.compact
        raise ArgumentError, 'At least one path is required' if @paths.empty?

        @model = model
        @dry_run = dry_run
        @logger = logger
        @chat_client = chat_client || Mayhem::OpenAI::ChatClient.new(logger: @logger)
      end

      def run
        stats = Hash.new(0)
        files = enumerate_files
        if files.empty?
          logger.warn 'No Markdown files matched the provided paths'
          return stats
        end

        files.each do |file|
          stats[:files_seen] += 1
          rewrite_file(file, stats)
        end
        log_summary(stats)
        stats
      end

      private

      def enumerate_files
        @paths.flat_map do |target|
          if File.directory?(target)
            Dir.glob(File.join(target, '**', '*.md'))
          elsif File.file?(target) && File.extname(target).casecmp('.md').zero?
            [target]
          else
            logger.warn "Skipping #{target}: not a readable Markdown file or directory"
            []
          end
        end.uniq.sort
      end

      def rewrite_file(path, stats)
        document = Mayhem::Support::FrontMatterDocument.load(path, logger:)
        unless document
          stats[:skipped_invalid_front_matter] += 1
          return
        end

        body = document.body.to_s.strip
        if body.empty?
          logger.debug "Skipping #{path}: empty body"
          stats[:skipped_empty] += 1
          return
        end

        rewritten = rewrite_body(document, body)
        if rewritten.nil? || rewritten.empty?
          stats[:errors] += 1
          logger.error "LLM returned no content for #{path}"
          return
        end

        cleaned = rewritten.strip
        if cleaned == body
          stats[:unchanged] += 1
          logger.debug "No AP style changes needed for #{path}"
          return
        end

        document.body = "#{cleaned.rstrip}\n"
        if @dry_run
          stats[:would_update] += 1
          logger.info "[dry-run] Would rewrite #{path}"
        else
          document.save
          stats[:updated] += 1
          logger.info "Rewrote #{path}"
        end
      rescue StandardError => e
        stats[:errors] += 1
        logger.error "Failed to rewrite #{path}: #{e.class} - #{e.message}"
      end

      def rewrite_body(document, body)
        metadata = contextual_metadata(document)
        prompt = <<~PROMPT
          You are editing copy for King County Solutions. Rewrite the Markdown body below so it
          follows the Associated Press Stylebook. Preserve the meaning, numerical values, lists,
          inline links, and emphasis. Make grammar, punctuation, and capitalization updates but do
          not add or remove sections, re-summarize, or invent details. Never output YAML front matter,
          explanations, or code fences—return only the revised Markdown body.

          Context:
          #{metadata.empty? ? 'n/a' : metadata}

          Original Markdown body:
          #{body}
        PROMPT

        @chat_client.call(
          messages: [
            { role: 'system', content: 'You are a meticulous copy editor who enforces AP style.' },
            { role: 'user', content: prompt }
          ],
          model: @model
        )
      end

      def contextual_metadata(document)
        front_matter = document.front_matter || {}
        keys = %w[title source source_url topics date start_date end_date]
        keys.map do |key|
          value = front_matter[key]
          next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

          formatted = value.is_a?(Array) ? value.join(', ') : value
          "#{key}: #{formatted}"
        end.compact.join("\n")
      end

      def log_summary(stats)
        summary = {
          files_seen: stats[:files_seen],
          updated: stats[:updated],
          would_update: stats[:would_update],
          unchanged: stats[:unchanged],
          skipped_empty: stats[:skipped_empty],
          skipped_invalid_front_matter: stats[:skipped_invalid_front_matter],
          errors: stats[:errors]
        }.map { |key, value| "#{key}=#{value}" }.join(', ')
        logger.info "AP style rewrite summary: #{summary}"
      end
    end
  end
end
