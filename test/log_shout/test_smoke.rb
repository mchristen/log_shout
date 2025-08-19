# frozen_string_literal: true

require "test_helper"

module LogShout
  class TestSmoke < Minitest::Test
    def test_smoke
      # A simple assertion that will always pass
      assert true
    end

    def test_constant_exists
      # Check that our main module exists
      assert defined?(LogShout)
    end
  end
end