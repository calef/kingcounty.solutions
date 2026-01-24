# frozen_string_literal: true

require 'json'
require_relative '../summarizer/base'
require_relative '../news/pruner'
require_relative '../models/news'

module Mayhem
  module News
    class PostSummarizer < Mayhem::Summarizer::Base
      MIN_SCRAPED_LENGTH = 400
      BOILERPLATE_PATTERNS = [
        /advanced features such as clipboard/i,
        /official federal government website/i,
        /before sharing sensitive information/i,
        /security of the connection/i,
        /you have safely connected to/i
      ].freeze

      def initialize(news_pruner: nil, **)
        super(**)
        @pruner = news_pruner ||
                  Mayhem::News::Pruner.new(images_pruner: @images_pruner)
      end

      private

      def model_class
        Mayhem::Models::News
      end

      def process_record(post, stats)
        process_post(post, stats)
      end

      def process_post(post, stats)
        record_id = post.id

        return if skip_locked_post?(post, record_id, stats)
        return if skip_unpublished_post?(post, record_id, stats)

        work_needed = determine_work_needed(post)
        return unless work_needed[:any_work_needed]

        return if skip_missing_source?(post, record_id, work_needed[:needs_summary], stats)

        summary_text = process_summary(post, record_id, work_needed, stats)
        return if work_needed[:needs_summary] && summary_text.nil?

        summary_text ||= post.body&.strip || ''
        summary_missing = summary_text.to_s.strip.empty?

        classify_post_topics(post, record_id, summary_text, work_needed[:needs_topic_titles], stats)
        classify_post_locations(post, record_id, summary_text, work_needed[:needs_location_titles], stats)

        finalize_post(post, record_id, summary_text, summary_missing, work_needed, stats)
      rescue StandardError => e
        stats[:errors] += 1
        logger.error "Error processing #{record_id}: #{e.class} - #{e.message}"
      end

      def skip_locked_post?(post, record_id, stats)
        return false unless post.locked? == true

        logger.debug "Skipping #{record_id}: locked is true"
        stats[:skipped_locked] += 1
        true
      end

      def skip_unpublished_post?(post, record_id, stats)
        return false if post.published?

        logger.debug "Skipping #{record_id}: published is false"
        stats[:skipped_unpublished] += 1
        backfill_unpublished_locations(post, record_id, stats)
        true
      end

      def backfill_unpublished_locations(post, record_id, stats)
        needs_location_titles = post['location_titles'].nil?
        return unless needs_location_titles && post.summarized? == true

        post.location_titles = []
        post.save!
        @pruner.unpublish(post)
        stats[:locations_backfilled] += 1
        logger.info "Set location_titles to [] and cleaned up images for unpublished #{record_id}"
      end

      def determine_work_needed(post)
        existing_summary = post.body&.strip
        needs_summary = post.summarized? != true
        needs_topic_titles = needs_classification_for_record?(post, 'topic_titles')
        needs_location_titles = needs_classification_for_record?(post, 'location_titles')
        summary_missing = post.summarized? == true && existing_summary.to_s.empty?

        {
          needs_summary: needs_summary,
          needs_topic_titles: needs_topic_titles,
          needs_location_titles: needs_location_titles,
          summary_missing: summary_missing,
          any_work_needed: needs_summary || needs_topic_titles || needs_location_titles || summary_missing
        }
      end

      def skip_missing_source?(post, record_id, needs_summary, stats)
        return false unless needs_summary && post.source_url.nil?

        logger.warn "Skipping #{record_id}: no source_url"
        stats[:skipped_missing_source] += 1
        true
      end

      def process_summary(post, record_id, work_needed, stats)
        return post.body&.strip unless work_needed[:needs_summary]

        content = fetch_article_content(post, record_id)
        return handle_empty_content(post, record_id, stats) if content[:article_text].to_s.empty?

        store_source_html(post, content[:html])
        summary_text = generate_summary(content[:article_text], post.source_url, record_id, stats)

        if summary_text.nil? || summary_text.empty?
          nil
        else
          post.summarized = true
          summary_text
        end
      end

      def fetch_article_content(post, record_id)
        feed_html = post.feed_content
        fallback_text = extract_text(feed_html)
        scraped_html = fetch_html(post.source_url)
        scraped_text = extract_text(scraped_html)

        if prefer_fallback_body?(scraped_text, fallback_text)
          logger.debug "Using fallback body for #{record_id}"
          article_text = fallback_text
          html = feed_html
        else
          article_text = scraped_text
          html = scraped_html
        end

        article_text ||= fallback_text
        html ||= feed_html
        article_text = truncate_text(article_text&.strip, record_id)

        { article_text: article_text, html: html }
      end

      def handle_empty_content(post, record_id, stats)
        logger.warn "Skipping #{record_id}: no usable content to summarize"
        stats[:failed_summary] += 1
        mark_unsummarizable(post, record_id)
        nil
      end

      def classify_post_topics(post, record_id, summary_text, needs_topic_titles, stats)
        return unless needs_topic_titles

        classified_topic_titles = classify_topics(summary_text)
        post.topic_titles = classified_topic_titles

        return unless classified_topic_titles.empty?

        logger.info "No topics matched for #{record_id}"
        stats[:missing_topics] += 1
      end

      def classify_post_locations(post, record_id, summary_text, needs_location_titles, stats)
        return unless needs_location_titles

        classified_locations = classify_locations(
          summary_text,
          content_title: post.title,
          content_source: post.organization_title
        )
        post.location_titles = classified_locations

        return unless classified_locations.empty?

        logger.info "No locations matched for #{record_id}"
        stats[:missing_locations] += 1
      end

      def finalize_post(post, record_id, summary_text, summary_missing, work_needed, stats)
        should_unpublish = summary_missing ||
                           (work_needed[:needs_topic_titles] && post.topic_titles.empty?) ||
                           (work_needed[:needs_location_titles] && post.location_titles.empty?)

        post.body = summary_text
        post.save!

        @pruner.unpublish(post) if should_unpublish

        stats[:updated] += 1
        logger.info "Updated #{record_id}"
      end

      def generate_summary(article_text, source_url, record_id, stats)
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

        system_message = 'You are a helpful assistant who writes summaries that follow The Associated Press Stylebook.'
        summary = call_openai(prompt, system_message, record_id, temperature: 0.7)

        return summary unless summary.nil? || summary.empty?

        logger.warn "Skipped #{record_id}: could not summarize"
        stats[:failed_summary] += 1
        nil
      end

      def log_summary(stats)
        summary_fields = {
          updated: stats[:updated],
          skipped_unpublished: stats[:skipped_unpublished],
          skipped_locked: stats[:skipped_locked],
          skipped_missing_source: stats[:skipped_missing_source],
          failed_summary: stats[:failed_summary],
          missing_topics: stats[:missing_topics],
          missing_locations: stats[:missing_locations],
          locations_backfilled: stats[:locations_backfilled],
          errors: stats[:errors]
        }
        summary_text = summary_fields.map { |key, value| "#{key}=#{value}" }.join(', ')
        logger.info "News summarization complete: #{summary_text}"
      end

      # Ensure required fields are present even when we cannot summarize due to missing content
      def mark_unsummarizable(post, _record_id)
        post.summarized = true
        post.topic_titles = []
        post.location_titles = []
        post.save!
        @pruner.unpublish(post)
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
