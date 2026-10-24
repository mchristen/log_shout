# frozen_string_literal: true

require "test_helper"

module LogShout
  class RegressionLoggingJob
    def self.run(logger)
      logger.info("logging restarted after reset")
      :completed
    end
  end

  class TestRegressions < Minitest::Test
    def test_failed_destination_does_not_drop_messages_for_healthy_destinations
      skip "requires /dev/full" unless File.exist?("/dev/full")
      failed = IORactor.new(handler: {type: :file, destination: "/dev/full"})
      healthy = IORactor.new(handler: {type: :memory})
      failed.write("trigger destination failure")
      assert_raises(Ractor::RemoteError) { failed.flush }

      logger = Logger.new(MultiIO.new([failed, healthy]))
      logger.info("deliver to healthy destination")

      # read is synchronous, so this also waits for the healthy worker's writes.
      assert_includes healthy.read, "deliver to healthy destination"
    ensure
      healthy&.close
      begin
        failed&.close
      rescue Ractor::RemoteError
        # The deliberately failed worker reports its original IO error on close.
      end
    end

    def test_reconfiguration_recovers_from_a_failed_worker
      skip "requires /dev/full" unless File.exist?("/dev/full")
      failed_config = File.join(@tmpdirpath, "failed.yml")
      File.write(failed_config, {
        defaultHandlers: ["failed", "healthy"],
        extraHandlers: {
          failed: {type: "file", path: "/dev/full"},
          healthy: {type: "memory"}
        }
      }.to_yaml)
      LogShout.configure(path: failed_config)
      old_logger = LogShout.get_logger(:app)
      old_logger.info("trigger destination failure")
      assert_raises(Ractor::RemoteError) { LogShout.flush }

      replacement_config = File.join(@tmpdirpath, "replacement.yml")
      File.write(replacement_config, {
        defaultHandlers: ["replacement"],
        extraHandlers: {replacement: {type: "memory"}}
      }.to_yaml)

      error = begin
        LogShout.configure(path: replacement_config)
        nil
      rescue Ractor::RemoteError => e
        e
      end
      assert_nil error, "A previously failed worker must not prevent installing a healthy configuration"
      assert_equal replacement_config, LogShout.config_file_path
      logger = LogShout.get_logger(:app)
      refute_same old_logger, logger
      logger.info("logging recovered")
      LogShout.flush
      assert_includes LogShout.get_handler(:replacement).read, "logging recovered"
    end

    def test_logging_ractor_can_start_immediately_after_reset
      config_path = File.join(@tmpdirpath, "restart.yml")
      File.write(config_path, {
        defaultHandlers: ["memory"],
        extraHandlers: {memory: {type: "memory"}}
      }.to_yaml)
      ENV["LOG_SHOUT_CONFIG_PATH"] = config_path
      LogShout.reset!

      job = LoggingRactor.start(target: RegressionLoggingJob, name: :app)
      assert_equal :completed, job.value
      LogShout.flush
      assert_includes LogShout.get_handler(:memory).read, "logging restarted after reset"
    ensure
      job&.join
      ENV.delete("LOG_SHOUT_CONFIG_PATH")
    end

    def test_null_default_handler_name_reports_configuration_error
      config_path = File.join(@tmpdirpath, "null-handler.yml")
      File.write(config_path, "defaultHandlers: [null]\n")

      assert_raises(LogShoutError) { LogShout.configure(path: config_path) }
    end

    def test_invalid_named_logger_handler_reports_configuration_error
      config_path = File.join(@tmpdirpath, "invalid-handler.yml")
      File.write(config_path, "loggers:\n  app:\n    handlers: [42]\n")

      assert_raises(LogShoutError) { LogShout.configure(path: config_path) }
    end

    def test_invalid_logger_name_reports_configuration_error
      config_path = File.join(@tmpdirpath, "invalid-logger.yml")
      File.write(config_path, "loggers:\n  42: {}\n")

      assert_raises(LogShoutError) { LogShout.configure(path: config_path) }
    end
  end
end
