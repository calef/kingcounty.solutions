# frozen_string_literal: true

require 'thread'
require 'time'

module Logging
  LEVELS = {
    'TRACE' => 0,
    'DEBUG' => 1,
    'INFO' => 2,
    'WARN' => 3,
    'ERROR' => 4,
    'FATAL' => 5
  }.freeze

  DEFAULT_LEVEL = 'WARN'

  class Logger
    def initialize(level_value:, program_name:)
      @level_value = level_value
      @program_name = program_name
      @mutex = Mutex.new
    end

    def log(level_name, message)
      value = LEVELS[level_name]
      return unless value
      return if value < @level_value

      stream = value >= LEVELS['WARN'] ? $stderr : $stdout
      timestamp = Time.now.utc.iso8601
      @mutex.synchronize { stream.puts "[#{level_name}] #{timestamp} #{@program_name}: #{message}" }
    end

    LEVELS.keys.each do |level_name|
      define_method(level_name.downcase) do |message|
        log(level_name, message)
      end
    end
  end

  module_function

  def build_logger(env_var:, default_level: DEFAULT_LEVEL, program_name: nil)
    env_level = ENV.fetch(env_var, default_level).to_s.upcase
    default_value = LEVELS.fetch(default_level.to_s.upcase, LEVELS[DEFAULT_LEVEL])
    level_value = LEVELS.fetch(env_level, default_value)
    program = program_name || File.basename($PROGRAM_NAME || __FILE__)
    Logger.new(level_value: level_value, program_name: program)
  end
end
