# frozen_string_literal: true

require 'yaml'
require 'test_helper'

class ConfigSmokeTest < Minitest::Test
  def test_config_is_loadable
    config = YAML.load_file('_config.yml')
    assert config.is_a?(Hash), 'Expected _config.yml to parse to a Hash'
  end
end
