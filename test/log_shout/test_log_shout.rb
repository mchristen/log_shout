# frozen_string_literal: true

require "test_helper"

module LogShout
  class TestLogShout < Minitest::Test
    def test_smoke
      # A simple assertion that will always pass
      assert true
    end

    def test_constant_exists
      # Check that our main module exists
      assert defined?(LogShout)
    end

    def test_get_logger
      setup_test_logger

      logger = LogShout.get_logger(:test_logger)
      assert_instance_of ::Logger, logger
      assert_equal "test_logger", logger.progname
      assert_equal ::Logger::INFO, logger.level
      logger.info("This is a test log message")
      logger2 = LogShout.get_logger(:test_logger)
      logger2.debug("This is a test debug log message")
      LogShout.flush
      assert_log_output("This is a test log message")
      refute_log_output("This is a test debug log message")

      multi_logger = LogShout.get_logger(:multi_logger)
      multi_logger.info("This is a second test log message")
      multi_logger.debug("This is a second test debug log message")
      LogShout.flush
      assert_log_output("This is a second test log message")
      assert_log_output("This is a second test debug log message")
      assert_memory_log_output("This is a second test debug log message")
      assert_memory_log_output("This is a second test log message")
    end

    def test_configure
      expected_path = File.expand_path("log_shout.yml", FileUtils.pwd)
      # even if configure is not called we should return the default config
      assert_equal LogShout::DEFAULT_CONFIG.serialize, LogShout.configuration
      refute LogShout.config_file_path
      # load the default config file path, since it doesn't exist
      # configuration should still return the defaults
      assert_equal expected_path, LogShout.configure
      assert_equal expected_path, LogShout.config_file_path
      assert_equal LogShout::DEFAULT_CONFIG.serialize, LogShout.configuration
    end

    def test_configure_with_environment_variable
      setup_test_logger
      expected_path = @expected_config_path
      # the environment variable should override the path being passed in
      ENV["LOG_SHOUT_CONFIG_PATH"] = expected_path

      LogShout.reset!

      assert_equal expected_path, LogShout.configure(path: "somejunk")
      assert_equal expected_path, LogShout.config_file_path
    end

    def test_configure_with_bad_path
      assert_raises LogShoutError do
        LogShout.configure(path: "somejunk")
      end
    end

    def test_configure_with_bad_yaml
      expected_path = File.expand_path("log_shout.yml", @tmpdirpath)

      FileUtils.touch(expected_path)
      File.write(expected_path, "`")

      exception = assert_raises LogShoutError do
        assert_equal expected_path, LogShout.configure(path: expected_path)
      end
      assert_equal "Failed to parse YAML configuration file at #{expected_path}: (#{expected_path}): found character" \
        " that cannot start any token while scanning for the next token at line 1 column 1",
        exception.message
      assert_equal LogShout::DEFAULT_CONFIG.serialize.freeze, LogShout.configuration
    end

    def test_configure_with_yaml
      expected_path = File.expand_path("log_shout.yml", @tmpdirpath)

      FileUtils.touch(expected_path)
      config = <<~CONFIG
        ---
        defaultLevel: debug
        defaultHandlers: [stdout]
        extraHandlers:
          memory_handler:
            type: memory
        loggers:
          test_logger:
            level: info
            handlers: [stdout, memory_handler]
      CONFIG
      File.write(expected_path, config)

      assert_equal expected_path, LogShout.configure(path: expected_path)
      assert_equal expected_path, LogShout.config_file_path
      config = LogConfigFile.new(
        defaultHandlers: [LogHandler.new(name: :stdout, type: LogDestination::STD_OUT)],
        defaultLevel: "debug",
        extraHandlers: {memory_handler: LogHandler.new(name: :memory_handler, type: LogDestination::MEMORY)},
        loggers: {test_logger: LogConfig.new(level: "info",
          handlers: [
            LogHandler.new(name: :stdout, type: LogDestination::STD_OUT),
            LogHandler.new(name: :memory_handler, type: LogDestination::MEMORY)
          ])}
      ).serialize.freeze
      assert_equal config, LogShout.configuration
    end

    def test_configure_with_invalid_configs
      expected_path = File.expand_path("log_shout.yml", @tmpdirpath)

      FileUtils.touch(expected_path)
      assert_raises LogShoutError do
        config = <<~CONFIG
          ---
          defaultLevel: debug
          defaultHandlers: [stdout]
          extraHandlers:
            stdout:
              type: file
              path: junk
        CONFIG
        File.write(expected_path, config)

        LogShout.configure(path: expected_path)
      end
      assert_raises LogShoutError do
        config = <<~CONFIG
          ---
          defaultLevel: debug
          defaultHandlers: [stdout]
          extraHandlers:
            file:
              type: notafile
              path: junk
        CONFIG
        File.write(expected_path, config)

        LogShout.configure(path: expected_path)
      end
      assert_raises LogShoutError do
        config = <<~CONFIG
          ---
          defaultLevel: debug
          defaultHandlers: [stdout]
          extraHandlers:
            file:
              type: file
        CONFIG
        File.write(expected_path, config)

        LogShout.configure(path: expected_path)
      end
    end

    def test_cleanup_handlers
      setup_test_logger
      LogShout.get_logger(:test_logger).info("TEST MESSAGE")
      LogShout.flush
    end
  end
end
