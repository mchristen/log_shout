# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/pride'

# Add the lib directory to the load path
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Require the main project file
require 'log_shout'

# You can add custom test helpers here
module TestHelpers
  # Example helper method
  def setup_test_logger
    Logger.new(IO::NULL)
  end
end

module Minitest
  class Test
    include TestHelpers
  end
end
