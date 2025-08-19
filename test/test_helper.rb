# frozen_string_literal: true

require "minitest/autorun"
require "minitest/pride"

# Add the lib directory to the load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Require the main project file
require "log_shout"

module Minitest
  class Test
    def setup
      super
      ENV["LOG_SHOUT_CONFIG_PATH"] = nil
      @tmpdirpath = Dir.mktmpdir
      LogShout.reset!
    end

    def teardown
      LogShout.reset!
      FileUtils.remove_entry_secure @tmpdirpath if @tmpdirpath && File.exist?(@tmpdirpath)
    end

    def assert_log_output(output)
      output_path = File.expand_path("test_output_log_shout.log", @tmpdirpath)
      assert File.exist?(output_path), "Log file should exist at #{output_path}"
      file_output = File.read(output_path)
      assert file_output.include?(output), "Log file should contain the expected output: #{output}\n\nBut instead contains:\n#{file_output}"
    end

    def refute_log_output(output)
      output_path = File.expand_path("test_output_log_shout.log", @tmpdirpath)
      assert File.exist?(output_path), "Log file should exist at #{output_path}"
      file_output = File.read(output_path)
      refute file_output.include?(output), "Log file should contain the expected output: #{output}\n\nBut instead contains:\n#{file_output}"
    end

    def assert_memory_log_output(expected_output)
      memory_handler = LogShout.get_handler(:memory)
      result = memory_handler.read
      assert result.include?(expected_output),
        "Memory handler should contain the expected output: #{expected_output}"
    end

    def setup_test_logger
      @expected_config_path = File.expand_path("log_shout.yml", @tmpdirpath)
      @output_path = File.expand_path("test_output_log_shout.log", @tmpdirpath)

      FileUtils.touch(@expected_config_path)
      config = <<~CONFIG
        ---
        defaultLevel: debug
        defaultHandlers: [stdout]
        extraHandlers:
          file:
            type: file
            path: #{@output_path}
          memory:
            type: memory
        loggers:
          LogShout::TestHelperModule::TestLogClass:
            level: info
            handlers: [file]
          LogShout::TestHelperModule::TestLogClass::custom_logger:
            level: debug
            handlers: [memory]
          test_logger:
            level: info
            handlers: [file]
          multi_logger:
            level: debug
            handlers: [memory, file]
      CONFIG
      File.write(@expected_config_path, config)

      assert_equal @expected_config_path, LogShout.configure(path: @expected_config_path)
    end
  end
end
