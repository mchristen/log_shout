# frozen_string_literal: true

module LogShout
  module Helper
    module ClassMethods
      def logger(extra_name: nil)
        logger_name = "#{name}::#{extra_name}" if extra_name
        logger_name ||= name
        LogShout.get_logger(logger_name.to_sym)
      end
    end

    def logger(extra_name: nil)
      self.class.logger(extra_name: extra_name)
    end

    def self.included(other)
      other.extend(ClassMethods)
    end
  end
end
