# frozen_string_literal: true

module LogShout
  class MultiIO
    def initialize(targets)
      @targets = targets
    end

    def write(message)
      @targets.each { |t| t.write(message) }
      nil
    end

    def close
      @targets.each(&:close)
      nil
    end

    def flush(wait_for_flush = true)
      @targets.each do |t|
        t.flush(wait_for_flush)
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
  end
end
