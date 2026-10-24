# frozen_string_literal: true

require "test_helper"

module LogShout
  class LoggingRactorTestJob
    def self.run(logger, number)
      logger.info("Hello from Ractor with args: #{number}!")
      logger.debug("Hello from Debug Ractor with args: #{number}!")
      true
    end
  end

  class TestRactors < Minitest::Test
    def setup
      super
      setup_test_logger
    end

    def test_ractor_smoke
      r = LoggingRactor.start(target: LoggingRactorTestJob, name: "test_logger", args: [42])
      assert r.value
      LogShout.flush
      assert_log_output "Hello from Ractor with args: 42"
      refute_log_output "Hello from Debug Ractor with args: 42"
    end

    def test_io_ractor
      handler = IORactor.new(handler: {type: :memory, name: :test_memory})
      handler.write("Hello, stdout!\n")
      handler.flush
      assert_equal "Hello, stdout!\n", handler.read
      handler.write("Hello, stdout2!\n")
      assert_equal "Hello, stdout!\nHello, stdout2!\n", handler.read
      handler.close
      handler.close
      assert handler.closed?
    end
  end
end
