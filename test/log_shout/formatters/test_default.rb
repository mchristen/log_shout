# frozen_string_literal: true

require "test_helper"

module LogShout
  module Formatters
    class TestDefault < Minitest::Test
      def test_smoke
        formatter = Default.new
        msg = formatter.call("INFO", Time.now, "TestProgname", "This is a test message")
        assert msg.include? "##{Process.pid}/#{(Thread.current.name || Thread.current.native_thread_id).to_s.rjust(6)}] I -- TestProgname: This is a test message\n"
      end
    end
  end
end
