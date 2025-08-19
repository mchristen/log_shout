# frozen_string_literal: true

require "test_helper"
module LogShout
  class TestHelperModule < Minitest::Test
    class TestLogClass
      include LogShout::Helper

      def self.test_logger_method
        logger.info("This is a test log message")
      end

      def self.test_custom_logger_method
        logger(extra_name: "custom_logger").debug("This is a custom test log message")
      end

      def instance_test_logger_method
        logger.info("This is an instance test log message")
      end

      def instance_test_custom_logger_method
        logger(extra_name: "custom_logger").debug("This is a custom instance test log message")
      end
    end

    def setup
      super
      setup_test_logger
    end

    def test_class_logger_method
      TestLogClass.test_logger_method
      TestLogClass.test_custom_logger_method
      LogShout.flush
      assert_log_output("LogShout::TestHelperModule::TestLogClass: This is a test log message")
      refute_log_output("LogShout::TestHelperModule::TestLogClass::custom_logger: This is a custom test log message")
      assert_memory_log_output("LogShout::TestHelperModule::TestLogClass::custom_logger: This is a custom test log message")
    end

    def test_isntance_logger_methods
      inst = TestLogClass.new
      inst.instance_test_logger_method
      inst.instance_test_custom_logger_method
      LogShout.flush
      assert_log_output("LogShout::TestHelperModule::TestLogClass: This is an instance test log message")
      refute_log_output("LogShout::TestHelperModule::TestLogClass::custom_logger: This is a custom instance test log message")
      assert_memory_log_output("LogShout::TestHelperModule::TestLogClass::custom_logger: This is a custom instance test log message")
    end
  end
end
