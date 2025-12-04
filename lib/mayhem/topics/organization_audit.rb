# frozen_string_literal: true

require 'json'
require 'yaml'
require 'fileutils'
require_relative '../logging'
require_relative '../support/front_matter_document'

module Mayhem
  module Topics
    class OrganizationAudit
      ORG_DIR = '_organizations'
      TOPIC_DIR = '_topics'
      POSTS_DIR = '_posts'
      CACHE_DIR = File.join('.jekyll-cache', 'topic_audit')
      DEFAULT_MODEL = ENV.fetch('OPENAI_TOPIC_AUDIT_MODEL', 'gpt-4o-mini')
      DEFAULT_MAX_POSTS = 5

      def initialize(
        client:,
        model: DEFAULT_MODEL,
        max_posts: DEFAULT_MAX_POSTS,
        force: false,
        output: nil,
        apply: false,
        org_dir: ORG_DIR,
        topic_dir: TOPIC_DIR,
        posts_dir: POSTS_DIR,
        cache_dir: CACHE_DIR,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @client = client
        @model = model
        @max_posts = max_posts
        @force = force
        @output = output
        @apply = apply
        @org_dir = org_dir
        @topic_dir = topic_dir
        @posts_dir = posts_dir
        @cache_dir = cache_dir
        @logger = logger
        @report = []
      end

      def run
        FileUtils.mkdir_p(@cache_dir)
        topics = load_topics
        organizations = load_organizations
        organizations.each do |org|
          process_org(org, topics)
        end
        write_report
        @report
      end

      private

      def load_topics
        Dir.glob(File.join(@topic_dir, '*.md')).each_with_object({}) do |path, acc|
          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          title = document.front_matter['title'] || default_title(path)
          summary = document.body.to_s.strip
          acc[title] = {
            'title' => title,
            'summary' => summary
          }
        end
      end

      def load_organizations
        Dir.glob(File.join(@org_dir, '*.md')).filter_map do |path|
          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          fm = document.front_matter
          {
            'path' => path,
            'title' => fm['title'] || default_title(path),
            'topics' => Array(fm['topics']).dup,
            'description' => [fm['summary'], fm['description']].compact.join(' '),
            'content' => document.body,
            'website' => fm['website']
          }
        end
      end

      def load_recent_posts(org_title)
        cached_posts = Dir.glob(File.join(@posts_dir, '**', '*.md')).filter_map do |path|
          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          fm = document.front_matter
          next unless fm['source'] == org_title

          {
            'title' => fm['title'],
            'date' => fm['date'],
            'excerpt' => (document.body || '').strip
          }
        end
        cached_posts.sort_by { |post| post['date'].to_s }.reverse.first(@max_posts)
      end

      def process_org(org, topics)
        cache_file = File.join(@cache_dir, cache_key(org['title']))
        posts = load_recent_posts(org['title'])

        @logger.info "Auditing #{org['title']}..."
        result = audit_org(org, topics, posts, cache_file)
        unless result
          @logger.warn "Skipping #{org['title']} due to parse errors"
          return
        end

        record_report(org, result)
        return unless @apply

        apply_changes(org, result)
      end

      def audit_org(org, topics, posts, cache_path)
        allowed_titles = topics.keys
        cached = cached_response(cache_path)
        filtered_cached = filter_result(cached, allowed_titles) if cached
        return filtered_cached if filtered_cached && !@force

        prompt = build_prompt(org, topics, posts)
        response = @client.chat(
          parameters: {
            model: @model,
            messages: [
              { role: 'system', content: 'You are a precise classification assistant who responds with JSON only.' },
              { role: 'user', content: prompt }
            ],
            temperature: 0.2
          }
        )

        content = response.dig('choices', 0, 'message', 'content')
        raise 'LLM returned empty response' unless content

        parsed = safe_parse_json(content, org['title'])
        filtered = filter_result(parsed, allowed_titles)
        File.write(cache_path, JSON.pretty_generate(filtered)) if filtered
        filtered
      end

      def cached_response(cache_path)
        return unless File.exist?(cache_path)

        JSON.parse(File.read(cache_path))
      rescue JSON::ParserError
        nil
      end

      def safe_parse_json(content, org_title)
        JSON.parse(content)
      rescue JSON::ParserError
        @logger.warn "Non-JSON response for #{org_title}: #{content.inspect}"
        nil
      end

      def build_prompt(org, topics, posts)
        topic_catalog = topics.map do |title, meta|
          summary = meta['summary'] || 'No summary provided.'
          "- #{title}: #{summary}".strip
        end.join("\n")

        snippet_lines = posts.map do |post|
          title = post['title'] || 'Untitled'
          date = post['date'] || 'Unknown date'
          raw_excerpt = post['excerpt']
          words = raw_excerpt&.split(/\s+/)
          snippet = words&.first(80)&.join(' ')
          "• #{title} (#{date}): #{snippet}"
        end
        post_lines = snippet_lines.join("\n")

        org_desc = [org['description'], org['content']&.strip].compact.join("\n\n")

        <<~PROMPT
          You are auditing topic coverage for organizations in a public social-service directory.

          Topic catalog:
          #{topic_catalog}

          Organization: #{org['title']}
          Existing topics: #{Array(org['topics']).join(', ')}
          Description:
          #{org_desc}

          Recent news:
          #{post_lines.empty? ? 'No recent posts.' : post_lines}

          Task: Determine which topics the organization currently provides based on the description and recent news. Only pick topics that clearly align; omit those without evidence. Return JSON with keys:
          {
            "topics_true": ["Topic Title", ...],
            "topics_false": ["Topic Title", ...],
            "topics_unclear": ["Topic Title", ...],
            "notes": "Optional rationale"
          }
          Only use topic titles from the catalog above; do not invent new topic names.
          "topics_true" should include all topics you are confident the organization covers (even if not currently listed). "topics_false" should list topics in the existing list that are unsupported. Use "topics_unclear" for anything ambiguous.
          Respond with JSON only.
        PROMPT
      end

      def filter_result(result, allowed_titles)
        return nil unless result.is_a?(Hash)

        allow = allowed_titles.to_set
        {
          'topics_true' => Array(result['topics_true']).select { |t| allow.include?(t) },
          'topics_false' => Array(result['topics_false']).select { |t| allow.include?(t) },
          'topics_unclear' => Array(result['topics_unclear']).select { |t| allow.include?(t) },
          'notes' => result['notes']
        }
      end

      def record_report(org, result)
        current = org['topics'] || []
        true_topics = Array(result['topics_true'])
        false_topics = Array(result['topics_false'])
        unclear = Array(result['topics_unclear'])

        additions = true_topics - current
        removals = false_topics & current

        @report << {
          org: org['title'],
          additions: additions,
          removals: removals,
          unclear: unclear,
          notes: result['notes']
        }
      end

      def apply_changes(org, result)
        additions = Array(result['topics_true']) - Array(org['topics'])
        removals = Array(result['topics_false']) & Array(org['topics'])
        return if additions.empty? && removals.empty?

        document = Mayhem::Support::FrontMatterDocument.load(org['path'], logger: @logger)
        return unless document

        updated_topics = (Array(document.front_matter['topics']) - removals + additions).uniq.sort
        document.front_matter['topics'] = updated_topics
        document.save
        @logger.info "Updated #{org['path']} topics: #{updated_topics.join(', ')}"
      end

      def write_report
        if @output
          File.write(@output, JSON.pretty_generate(@report))
          @logger.info "Report written to #{@output}"
        else
          print_report
        end
      end

      def print_report
        @report.each do |entry|
          @logger.info "== #{entry[:org]} =="
          @logger.info "Add:#{entry[:additions].empty? ? ' (none)' : " #{entry[:additions].join(', ')}"}"
          @logger.info "Remove:#{entry[:removals].empty? ? ' (none)' : " #{entry[:removals].join(', ')}"}"
          @logger.info "Unclear: #{entry[:unclear].join(', ')}" unless entry[:unclear].empty?
          @logger.info "Notes: #{entry[:notes]}" if entry[:notes]
        end
      end

      def cache_key(title)
        "#{title.downcase.gsub(/[^a-z0-9]+/, '_')}.json"
      end

      def default_title(path)
        File.basename(path, '.md').tr('-', ' ')
      end
    end
  end
end
