# frozen_string_literal: true

require_relative '../test_helper'
require 'mayhem/logging'
require 'stringio'
require 'json'

class LoggingTest < Minitest::Test
  def capture_streams
    old_out = $stdout
    old_err = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield $stdout, $stderr
  ensure
    $stdout = old_out
    $stderr = old_err
  end

  def test_logs_to_stdout_and_stderr_and_contains_expected_fields
    logger = Mayhem::Logging::Logger.new(level_value: Mayhem::Logging::LEVELS['DEBUG'], program_name: 'prog')

    capture_streams do |out, err|
      logger.debug('a debug')
      logger.info('an info')
      logger.warn('a warn')

      out.rewind
      err.rewind

      out_json = out.read.lines.map { |l| JSON.parse(l) }
      err_json = err.read.lines.map { |l| JSON.parse(l) }

      assert(out_json.any? { |r| r['severity_text'] == 'DEBUG' && r['body'] == 'a debug' })
      assert(out_json.any? { |r| r['severity_text'] == 'INFO' && r['body'] == 'an info' })
      assert(err_json.any? { |r| r['severity_text'] == 'WARN' && r['body'] == 'a warn' })

      # program_name and correlation_id present
      assert_equal 'prog', out_json.first['attributes']['program_name']
      assert out_json.first['attributes']['correlation_id']
    end
  end

  def test_unknown_level_does_not_output
    logger = Mayhem::Logging::Logger.new(level_value: Mayhem::Logging::LEVELS['DEBUG'], program_name: 'prog')

    capture_streams do |out, err|
      logger.log('NO_SUCH_LEVEL', 'ignored')
      out.rewind
      err.rewind

      assert_empty out.read
      assert_empty err.read
    end
  end

  def test_new_correlation_id_changes_id
    logger = Mayhem::Logging::Logger.new(level_value: Mayhem::Logging::LEVELS['DEBUG'], program_name: 'prog')
    old = logger.correlation_id
    logger.new_correlation_id

    refute_equal old, logger.correlation_id
  end

  def test_build_logger_respects_env_var
    ENV['TEST_LOG_LEVEL'] = 'ERROR'
    begin
      logger = Mayhem::Logging.build_logger(env_var: 'TEST_LOG_LEVEL', default_level: 'DEBUG', program_name: 'zzz')
      capture_streams do |out, err|
        logger.info('should be suppressed')
        out.rewind
        err.rewind

        assert_empty out.read
      end
    ensure
      ENV.delete('TEST_LOG_LEVEL')
    end
  end

  def test_singleton_logger_returns_same_instance
    Mayhem::Logging.reset_logger
    logger1 = Mayhem::Logging.logger
    logger2 = Mayhem::Logging.logger
    assert_same logger1, logger2
  end

  def test_can_override_singleton_logger
    Mayhem::Logging.reset_logger
    original = Mayhem::Logging.logger
    custom_logger = Mayhem::Logging::Logger.new(level_value: Mayhem::Logging::LEVELS['DEBUG'], program_name: 'custom')
    Mayhem::Logging.logger = custom_logger

    assert_same custom_logger, Mayhem::Logging.logger
    refute_same original, Mayhem::Logging.logger
  ensure
    Mayhem::Logging.reset_logger
  end

  def test_loggable_mixin_provides_logger_access
    test_class = Class.new do
      include Mayhem::Loggable

      def get_logger
        logger
      end
    end

    Mayhem::Logging.reset_logger
    instance = test_class.new
    assert_kind_of Mayhem::Logging::Logger, instance.get_logger
    assert_same Mayhem::Logging.logger, instance.get_logger
  ensure
    Mayhem::Logging.reset_logger
  end
end
