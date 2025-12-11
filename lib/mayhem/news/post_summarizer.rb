# frozen_string_literal: true

require 'json'
require 'nokogiri'
require 'open-uri'
require 'ruby/openai'
require_relative '../logging'
require_relative '../news/topic_classifier'
require_relative '../support/front_matter_document'
require_relative '../support/http_client'
require_relative '../support/content_utils'
require_relative '../feed_discovery'

module Mayhem
  module News
    class PostSummarizer
      POSTS_DIR = '_posts'
      TOPIC_DIR = '_topics'
      MAX_ARTICLE_CHARS = 20_000
      MIN_SCRAPED_LENGTH = 400
      BOILERPLATE_PATTERNS = [
        /advanced features such as clipboard/i,
        /official federal government website/i,
        /before sharing sensitive information/i,
        /security of the connection/i,
        /you have safely connected to/i
      ].freeze
      DEFAULT_MODEL = ENV.fetch('OPENAI_MODEL', 'gpt-4o-mini')
      DEFAULT_TOPIC_MODEL = ENV.fetch('OPENAI_TOPIC_MODEL', DEFAULT_MODEL)

      def initialize(
        posts_dir: POSTS_DIR,
        topic_dir: TOPIC_DIR,
        client: nil,
        topic_model: DEFAULT_TOPIC_MODEL,
        http_client: nil,
        logger: Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL'),
        topic_classifier: nil,
        location_checker: nil
      )
        @posts_dir = posts_dir
        @topic_dir = topic_dir
        @logger = logger
        @client = client || ::OpenAI::Client.new(access_token: ENV.fetch('OPENAI_API_KEY'))
        @http = http_client || Mayhem::Support::HttpClient.new(logger: @logger)
        @topic_classifier = topic_classifier ||
                            TopicClassifier.new(
                              topic_dir: @topic_dir,
                              model: topic_model,
                              client: @client,
                              logger: @logger
                            )
        @location_checker = location_checker
      end

      def run
        stats = Hash.new(0)
        Dir.glob(File.join(@posts_dir, '*.md')).each do |file_path|
          process_post(file_path, stats)
        end
        log_summary(stats)
        stats
      end

      private

      def process_post(file_path, stats)
        document = Mayhem::Support::FrontMatterDocument.load(file_path, logger: @logger)
        unless document
          stats[:skipped_no_frontmatter] += 1
          return
        end

        front_matter = document.front_matter
        if front_matter['locked'] == true
          @logger.debug "Skipping #{file_path}: locked is true"
          stats[:skipped_locked] += 1
          return
        end
        if front_matter['published'] == false
          @logger.debug "Skipping #{file_path}: published is false"
          stats[:skipped_unpublished] += 1
          return
        end

        needs_summary = front_matter['summarized'] != true
        needs_topics = Array(front_matter['topics']).empty?
        return unless needs_summary || needs_topics

        source_url = front_matter['source_url']
        if needs_summary && source_url.nil?
          @logger.warn "Skipping #{file_path}: no source_url"
          stats[:skipped_missing_source] += 1
          return
        end

        fallback_body = preferred_fallback_body(document)
        article_text = fetch_article_text(source_url) if source_url
        article_text = article_text&.strip
        if needs_summary && prefer_fallback_body?(article_text, fallback_body)
          article_text = fallback_body
          @logger.debug "Using fallback body for #{file_path}"
        end
        article_text ||= fallback_body
        article_text ||= document.body
        article_text = document.body if article_text.nil?
        if article_text && article_text.length > MAX_ARTICLE_CHARS
          @logger.info "Truncating #{file_path} article text from #{article_text.length} to #{MAX_ARTICLE_CHARS} chars"
          article_text = article_text[0, MAX_ARTICLE_CHARS]
        end

        summary_text = if needs_summary
                         result = generate_summary(article_text, source_url, file_path, stats)
                         if result.is_a?(Hash) && result.key?(:location_relevant)
                           # Store location relevance if it was checked
                           front_matter['location_relevant'] = result[:location_relevant]
                           unless result[:location_relevant]
                             stats[:marked_not_relevant] += 1
                           end
                           result[:summary]
                         else
                           result
                         end
                       else
                         document.body&.strip
                       end
        return if needs_summary && (summary_text.nil? || summary_text.empty?)

        front_matter['original_markdown_body'] ||= document.body&.strip if needs_summary
        front_matter['summarized'] = true if needs_summary
        summary_text ||= document.body&.strip || ''

        if needs_topics
          classified_topics = @topic_classifier.classify(summary_text)
          front_matter['topics'] = classified_topics
          if classified_topics.empty?
            @logger.info "No topics matched for #{file_path}"
            stats[:missing_topics] += 1
          end
        end

        # Mark as unpublished if not location relevant OR no topics
        if front_matter['location_relevant'] == false
          front_matter['published'] = false
        elsif needs_topics && Array(front_matter['topics']).empty?
          front_matter['published'] = false
        end

        document.front_matter = front_matter
        document.body = summary_text
        document.save
        stats[:updated] += 1
        @logger.info "Updated #{file_path}"
      rescue StandardError => e
        stats[:errors] += 1
        @logger.error "Error processing #{file_path}: #{e.class} - #{e.message}"
      end

      def generate_summary(article_text, source_url, file_path, stats)
        # If location checker is provided, combine both checks in one API call
        if @location_checker
          result = generate_summary_with_location_check(article_text, source_url, file_path, stats)
          return result[:summary] if result
          return nil
        end
        
        prompt = <<~PROMPT
          Summarize the following article in 200 words or less in Markdown format for a news aggregator blog, adhering to The Associated Press Stylebook.

          Article URL: #{source_url}

          In the summary:
            1. Do not include a link back to the source URL.
            2. Do not include an image if one is referenced in the text.
            3. Do not include any commentary or explanation about this process.
            4. Focus only on the provided text (do not mention if the content was truncated).
            5. Always write the summary in English, even if the source material uses another language.
            6. Do not include any headings or code blocks.
            7. Do not write that the article says something, just write what the article says. Do not write "The article discusses..." or "The article outlines...". Do write a summary of the article content.
            8. Use clear language no more complex than a 10th grade reading level.

          ARTICLE CONTENT:
          #{article_text}
        PROMPT

        attempts = 0
        while attempts < 3
          attempts += 1
          begin
            response = @client.chat(
              parameters: {
                model: DEFAULT_MODEL,
                messages: [
                  { role: 'system', content: 'You are a helpful assistant who writes summaries that follow The Associated Press Stylebook.' },
                  { role: 'user', content: prompt }
                ],
                temperature: 0.7
              }
            )
            if (error_message = response.dig('error', 'message'))
              @logger.warn "OpenAI error for #{file_path}: #{error_message}"
              break
            end

            summary = response.dig('choices', 0, 'message', 'content')&.strip
            return summary unless summary.to_s.empty?
          rescue Faraday::TooManyRequestsError
            @logger.warn "Rate limited, waiting 5 seconds before retry (attempt #{attempts})"
            sleep 5
          end
        end

        @logger.warn "Skipped #{file_path}: could not summarize"
        stats[:failed_summary] += 1
        nil
      end

      def generate_summary_with_location_check(article_text, source_url, file_path, stats)
        # Get location configuration for the prompt
        config = @location_checker.instance_variable_get(:@config) rescue {}
        locations = config.dig('location_relevance', 'locations') || []
        if locations.empty?
          locations = [{
            'name' => 'King County, Washington',
            'description' => 'King County, Washington includes cities such as Seattle, Bellevue, Renton, Kent, Auburn, Federal Way, and many others in the greater Seattle metropolitan area.'
          }]
        end

        location_names = locations.map { |loc| loc['name'] }.join(', ')

        prompt = <<~PROMPT
          You are tasked with two things:
          
          1. Summarize the following article in 200 words or less in Markdown format for a news aggregator blog, adhering to The Associated Press Stylebook.
          2. Determine if this content is relevant to an audience in: #{location_names}

          Article URL: #{source_url}

          For the summary:
            - Do not include a link back to the source URL
            - Do not include an image if one is referenced in the text
            - Focus only on the provided text
            - Always write in English
            - Do not include any headings or code blocks
            - Write what the article says, not that "the article discusses..."
            - Use clear language no more complex than a 10th grade reading level

          For location relevance:
            - Answer "yes" if the content explicitly mentions these locations or discusses matters that apply to residents there
            - Answer "no" if it's clearly about other locations
            - When in doubt, answer "yes"

          Respond in this exact format:
          LOCATION_RELEVANT: yes
          SUMMARY:
          [your summary here]

          ARTICLE CONTENT:
          #{article_text}
        PROMPT

        attempts = 0
        while attempts < 3
          attempts += 1
          begin
            response = @client.chat(
              parameters: {
                model: DEFAULT_MODEL,
                messages: [
                  { role: 'system', content: 'You are a helpful assistant who writes summaries following The Associated Press Stylebook and evaluates location relevance.' },
                  { role: 'user', content: prompt }
                ],
                temperature: 0.7
              }
            )
            
            if (error_message = response.dig('error', 'message'))
              @logger.warn "OpenAI error for #{file_path}: #{error_message}"
              break
            end

            content = response.dig('choices', 0, 'message', 'content')&.strip
            return nil if content.to_s.empty?

            # Parse the response
            if content =~ /LOCATION_RELEVANT:\s*(yes|no)/i
              is_relevant = $1.downcase == 'yes'
              summary = content.sub(/LOCATION_RELEVANT:\s*(?:yes|no)\s*SUMMARY:\s*/i, '').strip
              
              return { summary: summary, location_relevant: is_relevant }
            else
              # Fallback: if format not followed, assume relevant and use full content as summary
              return { summary: content, location_relevant: true }
            end
          rescue Faraday::TooManyRequestsError
            @logger.warn "Rate limited, waiting 5 seconds before retry (attempt #{attempts})"
            sleep 5
          end
        end

        @logger.warn "Skipped #{file_path}: could not generate combined summary and location check"
        stats[:failed_summary] += 1
        nil
      end

      def fetch_article_text(url)
        return nil unless url

        page = @http.fetch(url, accept: Mayhem::FeedDiscovery::ACCEPT_HTML, max_bytes: MAX_ARTICLE_CHARS)
        Mayhem::Support::ContentUtils.extract_text_from_html(
          page[:body],
          remove_elements: %w[script style nav header footer noscript iframe],
          content_selector: 'article, main, body'
        )
      rescue StandardError => e
        @logger.warn "Error fetching #{url}: #{e.class} - #{e.message}"
        nil
      end

      def log_summary(stats)
        summary_fields = {
          updated: stats[:updated],
          skipped_no_frontmatter: stats[:skipped_no_frontmatter],
          skipped_unpublished: stats[:skipped_unpublished],
          skipped_locked: stats[:skipped_locked],
          skipped_missing_source: stats[:skipped_missing_source],
          failed_summary: stats[:failed_summary],
          missing_topics: stats[:missing_topics],
          errors: stats[:errors]
        }
        summary_text = summary_fields.map { |key, value| "#{key}=#{value}" }.join(', ')
        @logger.info "News summarization complete: #{summary_text}"
      end

      def preferred_fallback_body(document)
        original = document.front_matter['original_markdown_body']
        original = original&.strip
        return original unless original.to_s.empty?

        body = document.body&.strip
        body.to_s.empty? ? nil : body
      end

      def prefer_fallback_body?(scraped_text, fallback_body)
        return false if fallback_body.to_s.empty?

        cleaned = scraped_text.to_s.strip
        return true if cleaned.empty?
        return true if BOILERPLATE_PATTERNS.any? { |pattern| cleaned.match?(pattern) }

        cleaned.length < MIN_SCRAPED_LENGTH && fallback_body.length > cleaned.length
      end
    end
  end
end
