# frozen_string_literal: true

module Mayhem
  module Support
    module ArticleBodySelectors
      SELECTORS = [
        '#news_content_body',
        '[id*="news_content_body"]',
        '.news_content_body',
        '[class*="news_content_body"]',
        '.news-body',
        '.article-body',
        '.article__body',
        '.news-article__body',
        'article .body'
      ].freeze
    end
  end
end
