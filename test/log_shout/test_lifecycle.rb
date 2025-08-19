# frozen_string_literal: true

require "test_helper"

module LogShout
  class TestLifecycle < Minitest::Test
    def test_logger_names_are_normalized
      setup_test_logger
      assert_same LogShout.get_logger(:test_logger), LogShout.get_logger("test_logger")
      assert_equal Logger::INFO, LogShout.get_logger("test_logger").level
    end

    def test_reconfiguration_drains_and_closes_old_handlers
      setup_test_logger
      old_handler = LogShout.get_handler(:file)
      old_logger = LogShout.get_logger(:test_logger)
      old_logger.info("queued before reconfiguration")
      LogShout.configure(path: @expected_config_path)
      assert old_handler.closed?
      assert_log_output "queued before reconfiguration"
      refute_same old_logger, LogShout.get_logger(:test_logger)
      refute LogShout.get_handler(:file).closed?
    end

    def test_reset_closes_handlers_and_logging_can_restart
      setup_test_logger
      old_handler = LogShout.get_handler(:memory)
      LogShout.reset!
      assert old_handler.closed?
      LogShout.reset!
      assert_instance_of Logger, LogShout.get_logger(:new)
    end

    def test_shutdown_is_idempotent_and_drains_writes
      setup_test_logger
      LogShout.get_logger(:test_logger).info("queued before shutdown")
      LogShout.close_handlers
      LogShout.close_handlers
      assert_log_output "queued before shutdown"
      assert LogShout.get_handler(:file).closed?
    end

    def test_closing_one_logger_keeps_shared_destinations_open
      setup_test_logger
      LogShout.get_logger(:test_logger).close
      LogShout.get_logger(:multi_logger).info("still usable")
      LogShout.flush
      assert_memory_log_output "still usable"
    end

    def test_builtin_handler_used_only_by_named_logger_is_created
      path = File.join(@tmpdirpath, "config.yml")
      File.write(path, "defaultHandlers: []\nloggers:\n  app:\n    handlers: [stderr]\n")
      LogShout.configure(path: path)
      assert_equal :stderr, LogShout.get_handler(:stderr).type
    end

    def test_failed_reconfiguration_preserves_existing_loggers
      setup_test_logger
      logger = LogShout.get_logger(:test_logger)
      assert_raises(LogShoutError) { LogShout.configure(path: File.join(@tmpdirpath, "missing")) }
      assert_same logger, LogShout.get_logger(:test_logger)
      logger.info("old configuration survived")
      LogShout.flush
      assert_log_output "old configuration survived"
    end

    def test_invalid_configuration_shapes_and_levels
      [nil, [], {defaultLevel: "loud"}, {defaultHandlers: "stdout"},
        {extraHandlers: []}, {loggers: []}, {loggers: {app: {level: "bad"}}},
        {loggers: {app: {handlers: "stdout"}}}].each do |config|
        assert_raises(LogShoutError) { LogShout.validate_config(config) }
      end
    end

    def test_bad_destination_fails_during_initialization
      error = assert_raises(Ractor::RemoteError) do
        IORactor.new(handler: {type: :file, destination: File.join(@tmpdirpath, "missing", "log")})
      end
      assert_instance_of Errno::ENOENT, error.cause
    end

    def test_invalid_handler_reports_argument_error
      error = assert_raises(Ractor::RemoteError) { IORactor.new(handler: {type: :invalid}) }
      assert_instance_of ArgumentError, error.cause
    end

    def test_worker_failure_wakes_flush_and_close
      skip "requires /dev/full" unless File.exist?("/dev/full")
      handler = IORactor.new(handler: {type: :file, destination: "/dev/full"})
      handler.write("cannot be written")
      error = assert_raises(Ractor::RemoteError) { handler.flush }
      assert_instance_of Errno::ENOSPC, error.cause
      assert_raises(Ractor::RemoteError) { handler.close }
      handler.close
      assert handler.closed?
    end

    def test_reply_ports_belong_to_each_calling_ractor
      handler = IORactor.new(handler: {type: :memory})
      worker = Ractor.new(handler) do |destination|
        destination.write("from worker")
        destination.flush
        destination.read
      end
      assert_equal "from worker", worker.value
      assert_equal "from worker", handler.read
    ensure
      handler&.close
    end

    def test_concurrent_thread_replies_are_not_mixed
      handler = IORactor.new(handler: {type: :memory})
      threads = 8.times.map do |i|
        Thread.new do
          handler.write("message #{i}\n")
          handler.flush
          handler.read
        end
      end
      threads.each { |thread| assert_kind_of String, thread.value }
      8.times { |i| assert_includes handler.read, "message #{i}\n" }
    ensure
      handler&.close
    end
  end
end
