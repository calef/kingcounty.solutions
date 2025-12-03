# frozen_string_literal: true

require 'date'
require 'json'
require 'ruby/openai'
require 'time'
require_relative '../logging'
require_relative '../news/topic_classifier'
require_relative '../support/front_matter_document'
require_relative '../support/slug_generator'

module Mayhem
  module News
    class WeeklySummaryGenerator
      POSTS_DIR = '_posts'
      TOPIC_DIR = '_topics'
      DEFAULT_MODEL = ENV.fetch('OPENAI_MODEL', 'gpt-5.1')
      DEFAULT_TOPIC_MODEL = ENV.fetch('OPENAI_TOPIC_MODEL', DEFAULT_MODEL)
      LLM_MAX_POSTS = ENV.fetch('WEEKLY_SUMMARY_LIMIT', '60').to_i

      def initialize(
        posts_dir: POSTS_DIR,
        client: nil,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        model: DEFAULT_MODEL,
        llm_limit: LLM_MAX_POSTS,
        topic_dir: TOPIC_DIR,
        topic_model: DEFAULT_TOPIC_MODEL,
        topic_classifier: nil
      )
        @posts_dir = posts_dir
        @logger = logger
        @model = model
        @llm_limit = llm_limit
        @client = client || OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
        @topic_dir = topic_dir
        @topic_model = topic_model
        @topic_classifier = topic_classifier ||
                            TopicClassifier.new(
                              topic_dir: @topic_dir,
                              model: @topic_model,
                              client: @client,
                              logger: @logger
                            )
      end

      def run
        override_date = parsed_date(ENV.fetch('WEEKLY_DATE', nil))
        week_reference = override_date || Date.today
        start_date, end_date = current_week_range(week_reference)
        posts = weekly_posts(start_date, end_date)

        if posts.empty?
          @logger.warn 'No posts found for the current week.'
          return
        end

        plan = build_theme_plan(posts)
        context = build_context(posts, start_date, end_date, plan)
        prompt = build_prompt(context)

        body, model_used = generate_summary_body(prompt, posts, start_date, end_date, plan)
        closing = "\n\nWe’ll continue to pull the most actionable updates from partner feeds each week. Let us know if there’s a topic you’d like covered in more depth."
        document_body = "#{body}#{closing}"
        topics = @topic_classifier.classify(document_body)
        summary_path = write_summary(start_date, end_date, document_body, model_used, topics)
        @logger.info "Created weekly summary: #{summary_path}"
      end

      private

      def current_week_range(today)
        days_since_saturday = (today.wday - 6) % 7
        week_end = today - days_since_saturday
        week_start = week_end - 6
        [week_start, week_end]
      end

      def parsed_date(value)
        return nil unless value

        Date.parse(value)
      rescue ArgumentError
        @logger.warn "Invalid date format: #{value}. Expected YYYY-MM-DD."
        nil
      end

      def weekly_posts(start_date, end_date)
        Dir.glob(File.join(@posts_dir, '*.md')).each_with_object([]) do |path, memo|
          basename = File.basename(path)
          match = basename.match(/\A(\d{4}-\d{2}-\d{2})-/)
          next unless match

          post_date = Date.parse(match[1])
          next unless post_date.between?(start_date, end_date)

          document = Mayhem::Support::FrontMatterDocument.load(path, logger: @logger)
          next unless document

          front_matter = document.front_matter
          next if front_matter['published'] == false

          memo << {
            id: basename,
            file: basename,
            slug: basename.sub(/\A\d{4}-\d{2}-\d{2}-/, '').sub(/\.md\z/, ''),
            path: path,
            date: post_date,
            title: front_matter['title'] || basename,
            source: front_matter['source'] || 'Unknown source',
            source_url: front_matter['source_url'],
            summary: normalize_excerpt(document.body || '')
          }
        end.sort_by { |post| [post[:date], post[:title]] }
      end

      def normalize_excerpt(body)
        paragraphs = body.split(/\n{2,}/).map(&:strip).reject(&:empty?)
        excerpt = paragraphs.first(3).join(' ')
        excerpt.gsub(/\s+/, ' ')[0..900]
      end

      def build_theme_plan(posts)
        sample_posts = posts.first(@llm_limit).map { |p| post_payload(p) }
        prompt = <<~PROMPT
          You are clustering weekly civic updates into editorial themes.
          Given the JSON array of posts below, create 3-4 high-level themes that capture the major narratives.
          Requirements:
            * Return a JSON object with keys:
                - "themes": array of objects { "title": string, "summary": string, "post_ids": [post_id, ...] }. Each theme should reference at least two unique post_ids.
                - "other_ids": array of remaining post_ids that didn't fit the main themes.
            * Keep titles concise (max 60 chars) and summaries under 200 chars.
            * Use each post_id at most once across themes + other_ids.
            * Prefer grouping by narrative impact rather than source.
            * Respond with JSON only.

          POSTS JSON:
          #{JSON.pretty_generate(sample_posts)}
        PROMPT

        raw = call_llm_chat(
          [
            { role: 'system', content: 'You analyze civic news items and cluster them into weekly themes.' },
            { role: 'user', content: prompt }
          ],
          temperature: 0.2
        )
        sanitized = strip_markdown_code_fence(raw)
        JSON.parse(sanitized)
      rescue StandardError => e
        @logger.warn "Theme planning failed (#{e.message}). Using fallback themes."
        fallback_theme_plan(posts)
      end

      def fallback_theme_plan(posts)
        post_ids = posts.first(@llm_limit).map { |p| p[:id] }
        {
          'themes' => [
            {
              'title' => 'Key regional updates',
              'summary' => 'Highlights across public safety, infrastructure, and community programs.',
              'post_ids' => post_ids.first(6)
            }
          ],
          'other_ids' => post_ids.drop(6)
        }
      end

      def strip_markdown_code_fence(text)
        stripped = text.strip
        return stripped unless stripped.start_with?('```')

        lines = stripped.lines
        lines.shift
        lines.pop if lines.last&.strip == '```'
        lines.join.strip
      end

      def build_context(posts, start_date, end_date, plan)
        lookup = posts.to_h { |p| [p[:id], post_payload(p)] }
        counts = Hash.new(0)
        posts.each { |post| counts[post[:source]] += 1 }
        top_sources = counts.sort_by { |_k, v| -v }.first(10).map do |source, count|
          { 'source' => source, 'count' => count }
        end

        themes = plan['themes'].map do |theme|
          {
            'title' => theme['title'],
            'summary' => theme['summary'],
            'posts' => theme['post_ids'].map { |id| lookup[id] }.compact
          }
        end

        {
          'window' => { 'start' => start_date.to_s, 'end' => end_date.to_s },
          'post_count' => posts.length,
          'top_sources' => top_sources,
          'themes' => themes,
          'other_posts' => plan.fetch('other_ids', []).map { |id| lookup[id] }.compact,
          'catalog' => lookup,
          'theme_plan' => plan
        }
      end

      def post_payload(post)
        {
          'id' => post[:id],
          'title' => post[:title],
          'date' => post[:date].to_s,
          'source' => post[:source],
          'url' => post[:source_url],
          'source_url' => post[:source_url],
          'summary' => post[:summary]
        }
      end

      def build_prompt(context)
        <<~PROMPT
          You are the editor for King County Solutions, a site that aggregates public-sector updates for residents in King County, Washington.

          TASK:
          • Study the provided JSON payload of partner posts for the week ending #{context['window']['end']}.
          • Use the provided "themes" array to organize your section headings (one section per theme, reusing the supplied titles).
          • Use each post's `url` value for inline links.
          • Write an engaging markdown article with the following structure:
            1. An opening paragraph summarizing how many posts we published and why this week matters.
            2. One section per theme (use the provided titles). Each section should have 1–2 short paragraphs weaving together the posts listed for that theme with inline links and context on why they matter. The inline links should not be within parentheses but linked from within the text.
            3. If `other_posts` is non-empty, add a short "### Other updates" paragraph covering them.
          • Keep the tone factual yet accessible, mirroring a newsroom briefing.
          • Mention source organizations in-line where relevant.
          • Do NOT fabricate links—only use the provided URLs.
          • Avoid repeating the same post in multiple sections unless critical.
          • Do NOT include a top-level H1 heading; start directly with the opening paragraph.
          • Limit the total response to roughly 450 words.

          JSON PAYLOAD:
          #{JSON.pretty_generate(context)}
        PROMPT
      end

      def generate_summary_body(prompt, posts, start_date, end_date, plan)
        [
          call_llm(prompt).strip,
          @model
        ]
      rescue StandardError => e
        @logger.warn "LLM generation failed (#{e.message}). Falling back to heuristic summary."
        [fallback_summary(posts, start_date, end_date, plan), 'fallback']
      end

      def fallback_summary(posts, start_date, end_date, plan = nil)
        total = posts.length
        lines = []
        lines << "We published #{total} partner update#{unless total == 1
                                                          's'
                                                        end} from #{start_date.strftime('%B %-d')} through #{end_date.strftime('%B %-d, %Y')}."
        plan ||= fallback_theme_plan(posts)
        lookup = posts.to_h { |p| [p[:id], p] }

        plan['themes'].each do |theme|
          refs = theme['post_ids'].map { |id| lookup[id] }.compact.first(4).map do |post|
            link = post[:source_url] ? "[#{post[:title]}](#{post[:source_url]})" : post[:title]
            "#{link} (#{post[:source]})"
          end
          next if refs.empty?

          lines << ''
          lines << "### #{theme['title']}"
          lines << "#{theme['summary']} Highlights: #{refs.join(', ')}."
        end

        other_refs = plan.fetch('other_ids', []).map { |id| lookup[id] }.compact.first(4).map do |post|
          link = post[:source_url] ? "[#{post[:title]}](#{post[:source_url]})" : post[:title]
          "#{link} (#{post[:source]})"
        end

        if other_refs.any?
          lines << ''
          lines << '### Other updates'
          lines << "Additional items: #{other_refs.join(', ')}."
        end

        lines.join("\n")
      end

      def call_llm(prompt)
        call_llm_chat(
          [
            { role: 'system',
              content: 'You are a concise civic-news editor who writes weekly recaps for King County residents.' },
            { role: 'user', content: prompt }
          ],
          temperature: 0.3
        )
      end

      def call_llm_chat(messages, temperature:)
        response = @client.chat(
          parameters: {
            model: @model,
            temperature: temperature,
            messages: messages
          }
        )
        if (error_message = response.dig('error', 'message'))
          raise "LLM request failed: #{error_message}"
        end

        content = response.dig('choices', 0, 'message', 'content')
        raise 'LLM response missing content' unless content

        content
      end

      def write_summary(start_date, end_date, body, model_used, topics)
        title = "King County Solutions Weekly Roundup: #{human_range(start_date, end_date)}"
        slug = Mayhem::Support::SlugGenerator.sanitized_slug(title)
        slug = 'post' if slug.empty?
        filename = "#{end_date}-#{slug}.md"
        dest = File.join(@posts_dir, filename)

        timezone_offset = Time.now.utc_offset
        publish_time = Time.new(end_date.year, end_date.month, end_date.day, 18, 0, 0, timezone_offset)

        front_matter = {
          'title' => title,
          'date' => publish_time.iso8601,
          'source' => 'King County Solutions',
          'summarized' => true,
          'openai_model' => model_used,
          'images' => [],
          'topics' => topics || []
        }

        document = Mayhem::Support::FrontMatterDocument.new(
          path: dest,
          front_matter: front_matter,
          body: body
        )
        document.save
        dest
      end

      def human_range(start_date, end_date)
        start_str = start_date.strftime('%B %-d')
        end_str = end_date.strftime('%B %-d, %Y')
        "#{start_str}–#{end_str}"
      end
    end
  end
end
