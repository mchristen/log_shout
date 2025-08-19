# frozen_string_literal: true

module LogShout
  module Formatters
    class Default < ::Logger::Formatter
      FORMAT = "[%s #%d/%6s] %.1s -- %s: %s\n"
      DATETIME_FORMAT = "%Y-%m-%d %H:%M:%S.%6N"

      def call(severity, time, progname, msg)
        thread_id = Thread.current.name || Thread.current.native_thread_id
        sprintf(FORMAT, time.strftime(DATETIME_FORMAT), Process.pid, thread_id, severity, progname, msg2str(msg))
      end
    end
  end
end
