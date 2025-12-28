# frozen_string_literal: true

require 'json'
require_relative '../logging'
require_relative '../models/organization'
require_relative '../models/topic'

module Mayhem
  module Topics
    class OrganizationAudit
      DEFAULT_MODEL = ENV.fetch('OPENAI_TOPIC_AUDIT_MODEL', 'gpt-4o-mini')
      DEFAULT_MAX_POSTS = 5

      def initialize(
        client:,
        model: DEFAULT_MODEL,
        max_posts: DEFAULT_MAX_POSTS,
        force: false,
        output: nil,
        apply: false,
        organization_model: Mayhem::Models::Organization,
        topic_model: Mayhem::Models::Topic,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
      )
        @client = client
        @model = model
        @max_posts = max_posts
        @force = force
        @output = output
        @apply = apply
        @organization_model = organization_model
        @topic_model = topic_model
        @logger = logger
        @report = []
      end

      def run
        topics = @topic_model.all.to_a
        organizations = @organization_model.all.to_a
        organizations.each do |org|
          process_org(org, topics)
        end
        write_report
        @report
      end

      private

      def load_recent_posts(org)
        posts = Array(org.news)
        posts.sort_by { |post| post.date.to_s }.reverse.first(@max_posts)
      end

      def process_org(org, topics)
        org_title = org.title
        posts = load_recent_posts(org)

        @logger.info "Auditing #{org_title}..."
        result = audit_org(org, topics, posts)
        unless result
          @logger.warn "Skipping #{org_title} due to parse errors"
          return
        end

        record_report(org, result)
        return unless @apply

        apply_changes(org, result)
      end

      def audit_org(org, topics, posts)
        allowed_titles = topics.map(&:title).compact
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

        parsed = safe_parse_json(content, org.title)
        filter_result(parsed, allowed_titles)
      end

      def safe_parse_json(content, org_title)
        candidate = normalize_response(content)
        JSON.parse(candidate)
      rescue JSON::ParserError
        @logger.warn "Non-JSON response for #{org_title}: #{content.inspect}"
        nil
      end

      def normalize_response(content)
        stripped = content.to_s.strip
        if (fenced = stripped.match(/\A```(?:json)?\s*(.+?)\s*```\z/m))
          stripped = fenced[1].strip
        end

        json_start = stripped.index('{')
        json_end = stripped.rindex('}')
        return stripped unless json_start && json_end && json_end >= json_start

        stripped[json_start..json_end]
      end

      def build_prompt(org, topics, posts)
        topic_catalog = topics.filter_map do |topic|
          title = topic.title
          next if title.nil? || title.empty?

          summary = topic.body.to_s.strip
          summary = 'No summary provided.' if summary.empty?
          "- #{title}: #{summary}".strip
        end.join("\n")

        snippet_lines = posts.map do |post|
          title = post.title
          date = post.date
          raw_excerpt = post.body.to_s.strip
          words = raw_excerpt&.split(/\s+/)
          snippet = words&.first(80)&.join(' ')
          "• #{title} (#{date}): #{snippet}"
        end
        post_lines = snippet_lines.join("\n")

        org_desc = [org['summary'], org['description'], org.body&.strip].compact.join("\n\n")

        <<~PROMPT
          You are auditing topic coverage for organizations in a public social-service directory.

          Topic catalog:
          #{topic_catalog}

          Organization: #{org.title}
          Existing topics: #{Array(org.topic_titles).join(', ')}
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
        current = org.topic_titles || []
        true_topics = Array(result['topics_true'])
        false_topics = Array(result['topics_false'])
        unclear = Array(result['topics_unclear'])

        additions = true_topics - current
        removals = false_topics & current

        @report << {
          org: org.title,
          additions: additions,
          removals: removals,
          unclear: unclear,
          notes: result['notes']
        }
      end

      def apply_changes(org, result)
        additions = Array(result['topics_true']) - Array(org.topic_titles)
        removals = Array(result['topics_false']) & Array(org.topic_titles)
        return if additions.empty? && removals.empty?

        updated_topics = (Array(org.topic_titles) - removals + additions).uniq.sort
        org['topic_titles'] = updated_topics
        org.save!
        @logger.info "Updated #{org.id} topic_titles: #{updated_topics.join(', ')}"
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
    end
  end
end
