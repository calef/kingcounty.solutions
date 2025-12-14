# frozen_string_literal: true

require_relative '../../test_helper'
require 'mayhem/front_matter/spacing_normalizer'

class FrontMatterSpacingNormalizerTest < Minitest::Test
  def test_inserts_blank_lines_around_list_when_followed_by_text
    body = <<~BODY
      Intro
      - One
      - Two
      Outro
    BODY

    normalized = Mayhem::FrontMatter::SpacingNormalizer.normalize(body)

    assert_includes normalized, "Intro\n\n- One"
    assert_includes normalized, "- Two\n\nOutro"
  end

  def test_does_not_add_blank_line_after_list_at_end
    body = <<~BODY
      Intro
      - One
      - Two
    BODY

    normalized = Mayhem::FrontMatter::SpacingNormalizer.normalize(body)

    assert_equal "Intro\n\n- One\n- Two", normalized
  end

  def test_trims_blank_lines_at_end
    body = "Intro\n\n\n"

    assert_equal 'Intro', Mayhem::FrontMatter::SpacingNormalizer.normalize(body)
  end

  def test_handles_empty_text
    assert_equal '', Mayhem::FrontMatter::SpacingNormalizer.normalize('')
  end
end
