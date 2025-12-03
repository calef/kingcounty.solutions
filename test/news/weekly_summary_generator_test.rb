require_relative '../test_helper'
require 'minitest/autorun'
require_relative '../../lib/mayhem/news/weekly_summary_generator'

class WeeklySummaryGeneratorTest < Minitest::Test
  def setup
    @tmp_posts = Dir.mktmpdir('posts')
    @logger = Mayhem::Logging.build_logger(env_var: 'LOG_LEVEL')
  end

  def teardown
    FileUtils.remove_entry(@tmp_posts)
  end

  def write_post(filename, front_matter, body = '')
    path = File.join(@tmp_posts, filename)
    content = Mayhem::Support::FrontMatterDocument.build_markdown(front_matter, body)
    File.write(path, content)
    path
  end

  def test_parsed_date_invalid_returns_nil
    gen = Mayhem::News::WeeklySummaryGenerator.new(posts_dir: @tmp_posts, logger: @logger, client: Object.new)
    assert_nil gen.send(:parsed_date, 'not-a-date')
  end

  def test_fallback_summary_pluralization_and_other_updates
    write_post('2025-11-25-one.md', { 'title' => 'One', 'source' => 'S1', 'source_url' => 'http://1', 'summarized' => true }, 'p1')
    write_post('2025-11-26-two.md', { 'title' => 'Two', 'source' => 'S2', 'source_url' => 'http://2', 'summarized' => true }, 'p2')
    gen = Mayhem::News::WeeklySummaryGenerator.new(posts_dir: @tmp_posts, logger: @logger, client: Object.new)
    posts = gen.send(:weekly_posts, Date.new(2025,11,24), Date.new(2025,11,30))
    assert_equal 2, posts.length

    # test fallback summary generation
    plan = gen.send(:fallback_theme_plan, posts)
    body = gen.send(:fallback_summary, posts, Date.new(2025,11,24), Date.new(2025,11,30), plan)
    assert_includes body, 'We published 2 partner updates'
  end

end
