require_relative 'test_helper'
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

      assert out_json.any? { |r| r['severity_text'] == 'DEBUG' && r['body'] == 'a debug' }
      assert out_json.any? { |r| r['severity_text'] == 'INFO' && r['body'] == 'an info' }
      assert err_json.any? { |r| r['severity_text'] == 'WARN' && r['body'] == 'a warn' }

      # program_name and correlation_id present
      assert out_json.first['attributes']['program_name'] == 'prog'
      assert out_json.first['attributes']['correlation_id']
    end
  end

  def test_unknown_level_does_not_output
    logger = Mayhem::Logging::Logger.new(level_value: Mayhem::Logging::LEVELS['DEBUG'], program_name: 'prog')

    capture_streams do |out, err|
      logger.log('NO_SUCH_LEVEL', 'ignored')
      out.rewind; err.rewind
      assert out.read.empty?
      assert err.read.empty?
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
        out.rewind; err.rewind
        assert out.read.empty?
      end
    ensure
      ENV.delete('TEST_LOG_LEVEL')
    end
  end
end
