# frozen_string_literal: true

module LogShout
  class IORactor
    def initialize(handler: {})
      @handler = handler
      @cmds = Ractor::Port.new
      @r = Ractor.new(handler, @cmds) do |handler, cmds|
        IORactor.execute_ractor(handler, cmds)
      end
    end

    def self.execute_ractor(handler, cmds)
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
        raise ArgumentError, "Invalid handler definition: #{h.inspect}"
      end

      io.sync = true if io.respond_to?(:sync=)

      begin
        loop do
          op, *args = Ractor.receive
          case op
          when :write
            s = args.fetch(0)
            io.write(s)
          when :flush
            io.flush if io.respond_to?(:flush)
            cmds.send([:flush])
          when :close
            break
          when :read
            if io.is_a?(StringIO)
              cmds.send([:read, io.string])
            else
              cmds.send([:read, nil])
            end
          else
            # ignore/extend
          end
        end
      ensure
        io.close if io.respond_to?(:close) && !io.closed?
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

    # --- IO-like API ---
    def write(str)
      s = String(str)            # ensure String
      @r.send([:write, s])
      s.bytesize
    end

    def flush(wait_for_flush = true)
      @r.send([:flush])
      @cmds.receive if wait_for_flush
      nil
    end

    # only useful for debugging memory handler
    def read
      @r.send([:read])
      @cmds.receive[1]
    end

    def close
      @r.send([:flush])
      @r.send([:close])
      @cmds.receive
      @r.value                      # wait for :closed
      nil
    end
  end
end
