# frozen_string_literal: true

module LogShout
  class LoggingRactor
    # caller passes a shareable target (Module/Class) and a method Symbol
    def self.start(target:, method: :run, name: nil, args: [])
      name ||= target.name
      handlers = LogShout.get_handlers_for(name).freeze
      level = ::Logger.const_get(LogShout.get_level_for_name(name).upcase)
      logdev = LogShout::MultiIO.new(handlers)
      r = Ractor.new(level, logdev, args, name: name) do |level, logdev, a|
        logger = ::Logger.new(logdev,
          level: level,
          progname: Ractor.current.name,
          formatter: LogShout::Formatters::Default.new)
        # Call a shareable entrypoint; e.g., MyJob.run(logger, *a)
        job = Ractor.receive     # receive [ModuleOrClass, :method]
        receiver = Ractor.receive
        job.public_send(receiver, logger, *a)
      ensure
        logdev.flush(false)
      end

      # Send the callable in a ractor-safe way (two shareable messages)
      r.send(target)
      r.send(method)
      r
    end
  end
end
