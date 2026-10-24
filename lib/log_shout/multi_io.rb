# frozen_string_literal: true

module LogShout
  class MultiIO
    def initialize(targets)
      @targets = targets
    end

    def write(message)
      each_target { |target| target.write(message) }
      nil
    end

    def close
      # Destinations belong to LogShout and may be used by other loggers.
      flush
      nil
    end

    def flush(wait_for_flush = true)
      each_target do |target|
        target.flush(wait_for_flush)
      end
      nil
    end

    # only useful for debugging memory handler
    def read(handler)
      @targets.each do |t|
        next unless t.name == handler
        return t.read
      end
      nil
    end

    private

    # Report failures after giving every destination a chance to process the call.
    def each_target
      errors = []
      @targets.each do |target|
        yield target
      rescue => e
        errors << e
      end
      HandlerErrors.raise_if_any(errors)
    end
  end
end
