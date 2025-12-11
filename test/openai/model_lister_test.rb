# frozen_string_literal: true

require_relative '../test_helper'
require 'minitest/autorun'
require_relative '../../lib/mayhem/openai/model_lister'

class ModelListerTest < Minitest::Test
  class FakeModelClient
    attr_reader :listed

    def initialize(models)
      @models = models
      @listed = false
    end

    def models
      self
    end

    def list
      @listed = true
      { 'data' => @models.map { |id| { 'id' => id } } }
    end
  end

  def test_run_prints_each_model_identifier
    fake_client = FakeModelClient.new(%w[foo bar baz])
    lister = Mayhem::OpenAI::ModelLister.new(client: fake_client)

    output, _ = capture_io do
      lister.run
    end

    assert_equal "foo\nbar\nbaz\n", output
    assert fake_client.listed
  end

  def test_run_handles_empty_list
    fake_client = FakeModelClient.new([])
    lister = Mayhem::OpenAI::ModelLister.new(client: fake_client)

    output, _ = capture_io do
      lister.run
    end

    assert_equal '', output
  end
end
