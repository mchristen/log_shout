# frozen_string_literal: true

module LogShout
  class IORactor
    def initialize(handler: {})
      @handler = handler
      @closed = false
      @r = Ractor.new(handler) do |definition|
        IORactor.execute_ractor(definition)
      end
      request(:ready)
    end

    def self.execute_ractor(handler)
      io = case handler[:type]
      when nil, :stdout
        IO.for_fd(1, autoclose: false)
      when :stderr
        IO.for_fd(2, autoclose: false)
      when :file
        File.open(handler.fetch(:destination), "a")
      when :memory
        StringIO.new
      else
        raise ArgumentError, "Invalid handler definition: #{handler.inspect}"
      end
      io.sync = true if io.respond_to?(:sync=)

      begin
        loop do
          op, arg, reply = Ractor.receive
          result = case op
          when :ready
            nil
          when :write
            io.write(arg)
          when :flush
            io.flush
            nil
          when :read
            io.is_a?(StringIO) ? io.string : nil
          when :close
            break
          end
          reply&.send([:ok, result])
        end
      ensure
        io.close unless io.closed?
      end
      :closed
    end

    def name
      @handler[:name]
    end

    def type
      @handler[:type]
    end

    def destination
      @handler[:destination]
    end

    def closed?
      @closed || @r.default_port.closed?
    end

    def write(str)
      raise IOError, "closed log handler" if closed?
      s = String(str)
      @r.send([:write, s])
      s.bytesize
    end

    def flush(wait_for_flush = true)
      if wait_for_flush
        request(:flush)
      else
        @r.send([:flush])
      end
      nil
    end

    def read
      request(:read)
    end

    def close
      return if @closed
      begin
        begin
          @r.send([:close])
        rescue Ractor::ClosedError
          # Join below still reports the worker's original failure.
        end
        @r.join
      ensure
        @closed = true
      end
      nil
    end

    private

    # A fresh reply port belongs to the calling Ractor. Monitoring that same
    # port also wakes the caller if the worker dies before replying.
    def request(op)
      raise IOError, "closed log handler" if @closed
      reply = Ractor::Port.new
      @r.monitor(reply)
      begin
        @r.send([op, nil, reply])
      rescue Ractor::ClosedError
        @r.join
        raise IOError, "closed log handler"
      end
      response = reply.receive
      unless response.is_a?(Array)
        @r.join
        raise IOError, "log handler terminated before replying"
      end
      response[1]
    ensure
      if reply
        @r.unmonitor(reply)
        reply.close
      end
    end
  end
end
