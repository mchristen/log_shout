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
      assert_log_output "Hello from Ractor with args: 42"
      refute_log_output "Hello from Debug Ractor with args: 42"
    end

    def test_io_ractor
      cmds = Ractor::Port.new
      Ractor.current.send([:write, "Hello, stdout!\n"])
      Ractor.current.send([:flush])
      Ractor.current.send([:read])
      Ractor.current.send([:write, "Hello, stdout2!\n"])
      Ractor.current.send([:read])
      Ractor.current.send([:close])
      assert_equal :closed, IORactor.execute_ractor({type: :memory, name: :test_memory}, cmds)
      assert_equal [:flush], cmds.receive
      assert_equal [:read, "Hello, stdout!\n"], cmds.receive
      assert_equal [:read, "Hello, stdout!\nHello, stdout2!\n"], cmds.receive
    end
  end
end
