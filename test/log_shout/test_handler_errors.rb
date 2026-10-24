# frozen_string_literal: true

require "test_helper"

module LogShout
  class TestHandlerErrors < Minitest::Test
    def test_write_reports_all_failures_and_delivers_to_healthy_destination
      first = IORactor.new(handler: {type: :memory})
      second = IORactor.new(handler: {type: :memory})
      healthy = IORactor.new(handler: {type: :memory})
      first.close
      second.close

      error = assert_raises(HandlerErrors) do
        MultiIO.new([first, healthy, second]).write("still delivered")
      end
      assert_equal 2, error.errors.length
      assert error.errors.all? { |failure| failure.is_a?(IOError) }
      assert error.errors.frozen?
      assert_equal "still delivered", healthy.read
    ensure
      first&.close
      second&.close
      healthy&.close
    end

    def test_flush_reports_all_failures
      first = IORactor.new(handler: {type: :memory})
      second = IORactor.new(handler: {type: :memory})
      first.close
      second.close

      error = assert_raises(HandlerErrors) { MultiIO.new([first, second]).flush }
      assert_equal 2, error.errors.length
      assert error.errors.all? { |failure| failure.is_a?(IOError) }
    ensure
      first&.close
      second&.close
    end

    def test_single_failure_preserves_original_exception
      failure = IOError.new("one failed destination")
      destination = Object.new
      destination.define_singleton_method(:write) { |_message| raise failure }

      error = assert_raises(IOError) { MultiIO.new([destination]).write("message") }
      assert_same failure, error
    end

    def test_error_message_includes_each_exception
      first = IOError.new("first destination failed")
      second = ArgumentError.new("second destination failed")
      error = HandlerErrors.new([first, second])

      assert_includes error.message, "IOError: first destination failed"
      assert_includes error.message, "ArgumentError: second destination failed"
      assert_equal [first, second], error.errors
    end

    def test_shutdown_reports_both_worker_failures_and_closes_healthy_handler
      configure_failed_workers
      healthy = LogShout.get_handler(:healthy)

      error = assert_raises(HandlerErrors) { LogShout.close_handlers }
      assert_equal 2, error.errors.length
      assert error.errors.all? { |failure| failure.cause.is_a?(Errno::ENOSPC) }
      assert_includes error.message, "Errno::ENOSPC"
      assert healthy.closed?
      LogShout.close_handlers
    end

    def test_reconfiguration_reports_every_failed_worker_and_recovers
      configure_failed_workers

      _stdout, stderr = capture_io { LogShout.configure }
      assert_equal 2, stderr.scan("LogShout replaced failed handlers:").length
      assert_equal 2, stderr.scan("Errno::ENOSPC").length
      refute LogShout.get_handler(:stdout).closed?
    end

    private

    def configure_failed_workers
      skip "requires /dev/full" unless File.exist?("/dev/full")
      path = File.join(@tmpdirpath, "failed.yml")
      File.write(path, {
        defaultHandlers: ["first", "second", "healthy"],
        extraHandlers: {
          first: {type: "file", path: "/dev/full"},
          second: {type: "file", path: "/dev/full"},
          healthy: {type: "memory"}
        }
      }.to_yaml)
      LogShout.configure(path: path)
      LogShout.get_logger(:app).info("trigger both failures")
      error = assert_raises(HandlerErrors) { LogShout.flush }
      assert_equal 2, error.errors.length
    end
  end
end
