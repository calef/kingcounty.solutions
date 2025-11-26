# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'time'

module Mayhem
  # Structured logging helpers used by Mayhem services.
  module Logging
    LEVELS = {
      'TRACE' => 0,
      'DEBUG' => 1,
      'INFO' => 2,
      'WARN' => 3,
      'ERROR' => 4,
      'FATAL' => 5
    }.freeze
    SEVERITY_NUMBER = {
      'TRACE' => 1,
      'DEBUG' => 5,
      'INFO' => 9,
      'WARN' => 13,
      'ERROR' => 17,
      'FATAL' => 21
    }.freeze

    DEFAULT_LEVEL = 'WARN'

    # Wraps JSON-based logging semantics for shared clients.
    class Logger
      attr_reader :correlation_id

      def initialize(level_value:, program_name:, correlation_id: nil)
        @level_value = level_value
        @program_name = program_name
        @correlation_id = correlation_id || generate_correlation_id
        @mutex = Mutex.new
      end

      def new_correlation_id
        @correlation_id = generate_correlation_id
      end

      def log(level_name, message)
        value = LEVELS[level_name]
        return unless value
        return if value < @level_value

        stream = log_stream(value)
        record = build_record(level_name, message, value)
        write_record(stream, record)
      end

      LEVELS.each_key do |level_name|
        define_method(level_name.downcase) do |message|
          log(level_name, message)
        end
      end

      private

      def log_stream(value)
        value >= LEVELS['WARN'] ? $stderr : $stdout
      end

      def build_record(level_name, message, value)
        timestamp = Time.now.utc.iso8601
        {
          'timestamp' => timestamp,
          'severity_text' => level_name,
          'severity_number' => SEVERITY_NUMBER[level_name] || value,
          'body' => message.to_s,
          'attributes' => {
            'program_name' => @program_name,
            'correlation_id' => @correlation_id,
            'thread' => Thread.current.object_id
          }
        }
      end

      def write_record(stream, record)
        @mutex.synchronize do
          stream.puts JSON.generate(record)
        end
      end

      def generate_correlation_id
        SecureRandom.uuid
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

    def new_correlation_id(logger)
      logger.new_correlation_id
    end
  end
end
