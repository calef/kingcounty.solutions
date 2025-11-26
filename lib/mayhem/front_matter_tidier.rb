# frozen_string_literal: true

require 'yaml'
require 'mayhem/logging'
require 'mayhem/support/front_matter_document'

module Mayhem
  class FrontMatterTidier
    def initialize(logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'))
      @logger = logger
    end

    # Rewrites every Markdown target (file or directory) so the front matter
    # keys are alphabetically ordered and the document is wrapped with a single
    # leading/trailing delimiter plus a blank line before the body.
    def tidy(target_paths)
      Array(target_paths).each do |target|
        tidy_target(target)
      end
    end

    # Public helper that normalizes a Markdown string according to the tidy rules.
    def tidy_markdown(content)
      result = Mayhem::Support::FrontMatterDocument.parse(content)
      front_matter = sorted_front_matter(result.front_matter)
      body = normalize_body(result.body)
      build_document(front_matter, body)
    end

    private

    def tidy_target(target)
      path = File.expand_path(target)
      if File.directory?(path)
        tidy_directory(path)
      elsif markdown_file?(path)
        tidy_file(path)
      else
        @logger.warn "Skipping non-Markdown target #{target}"
      end
    rescue Errno::ENOENT
      @logger.warn "Target not found: #{target}"
    end

    def tidy_directory(directory)
      Dir.glob(File.join(directory, '**', '*.md')).sort.each do |file|
        tidy_file(file)
      end
    end

    def tidy_file(path)
      content = File.read(path)
      normalized = tidy_markdown(content)
      return if normalized == content

      File.write(path, normalized)
      @logger.info "Tidied front matter in #{path}"
    rescue Mayhem::Support::FrontMatterDocument::ParseError => e
      @logger.warn "Skipping #{path}: #{e.message}"
    end

    def markdown_file?(path)
      File.file?(path) && path.downcase.end_with?('.md')
    end

    def sorted_front_matter(front_matter)
      front_matter.to_a.sort_by { |key, _| key.to_s }.to_h
    end

    def normalize_body(body)
      body.to_s.sub(/\A\n+/, '')
    end

    def build_document(front_matter, body)
      yaml_segment = build_yaml_segment(front_matter)
      body_segment = body.to_s

      sections = ['---', yaml_segment, '---', '']
      sections << body_segment unless body_segment.empty?
      content = sections.join("\n")
      content << "\n" unless content.end_with?("\n")
      content
    end

    def build_yaml_segment(front_matter)
      return '' if front_matter.empty?

      segment = YAML.dump(front_matter)
      segment = segment.sub(/\A---\s*\n/, '')
      segment = segment.sub(/\.\.\.\s*\n\z/, '')
      segment.rstrip
    end
  end
end
