# frozen_string_literal: true

require "fileutils"
require "yaml"
require "logger"
require "stringio"

require "log_shout/helper"
require "log_shout/multi_io"
require "log_shout/io_ractor"
require "log_shout/logging_ractor"
require "log_shout/version"
require "log_shout/formatters/default"

module LogShout
  class LogShoutError < StandardError; end

  # Replace the Sorbet enum with a plain Ruby value-object enum
  class LogDestination
    attr_reader :name
    private_class_method :new

    def initialize(name)
      @name = name
    end

    def to_sym
      @name
    end

    def to_s
      @name.to_s
    end

    # Keep the same API used elsewhere
    def serialize
      @name
    end

    def ==(other)
      other.is_a?(LogDestination) && other.name == name
    end

    alias_method :eql?, :==

    def hash
      name.hash
    end

    STD_OUT = new(:stdout)
    STD_ERR = new(:stderr)
    FILE = new(:file)
    MEMORY = new(:memory)

    ALL = [STD_OUT, STD_ERR, FILE, MEMORY].freeze

    def self.from(value)
      return value if value.is_a?(LogDestination)
      sym = value.to_s.downcase.to_sym
      ALL.find { |v| v.name == sym } || (raise ArgumentError, "Unknown destination: #{value.inspect}")
    end
  end

  # Sorbet-free structs with the same public API

  LogHandler = Struct.new(:name, :type, :destination, keyword_init: true) do
    def ==(other)
      other.is_a?(LogHandler) && name == other.name
    end

    def serialize
      {
        name: name,
        type: type.respond_to?(:serialize) ? type.serialize : type.to_sym,
        destination: destination
      }
    end
  end

  LogConfig = Struct.new(:level, :handlers, keyword_init: true) do
    def ==(other)
      other.is_a?(LogConfig) &&
        level == other.level &&
        handlers == other.handlers
    end

    def serialize
      {
        level: level,
        handlers: handlers.map(&:serialize)
      }
    end
  end

  LogConfigFile = Struct.new(:loggers, :extraHandlers, :defaultLevel, :defaultHandlers, keyword_init: true) do
    def ==(other)
      other.is_a?(LogConfigFile) &&
        loggers == other.loggers &&
        extraHandlers == other.extraHandlers &&
        defaultLevel == other.defaultLevel &&
        defaultHandlers == other.defaultHandlers
    end

    def serialize
      {
        loggers: loggers.transform_values(&:serialize),
        extraHandlers: extraHandlers.transform_values(&:serialize),
        defaultLevel: defaultLevel,
        defaultHandlers: defaultHandlers.map(&:serialize)
      }
    end
  end

  BUILTIN_HANDLERS = {
    stdout: LogHandler.new(name: :stdout, type: LogDestination::STD_OUT),
    stderr: LogHandler.new(name: :stderr, type: LogDestination::STD_ERR)
  }

  DEFAULT_CONFIG = LogConfigFile.new(
    defaultLevel: "INFO",
    defaultHandlers: [BUILTIN_HANDLERS[:stdout]],
    loggers: {},
    extraHandlers: {}
  )

  @loggers = {}

  def self.configure(path: nil)
    default_path = File.expand_path("log_shout.yml", FileUtils.pwd)
    requested_path = ENV.fetch("LOG_SHOUT_CONFIG_PATH", path)
    @config_file_path = requested_path || default_path
    @validated_config = if File.exist?(@config_file_path)
      begin
        validate_config(YAML.load_file(@config_file_path, symbolize_names: true))
      rescue Psych::SyntaxError => e
        raise LogShoutError,
          "Failed to parse YAML configuration file at " \
                         "#{@config_file_path}: #{e.message}"
      end
    elsif requested_path
      raise LogShoutError, "Configuration file not found at #{requested_path}"
    end
    # this replaces the typed objects for validating the parsed YAML
    # with plain old Ruby objects that are frozen to prevent modification
    # which means we can use them in Ractors
    @validated_config ||= DEFAULT_CONFIG
    @validated_config = @validated_config.serialize.freeze
    create_handlers
    @config_file_path
  end

  def self.create_handlers
    raise LogShoutError, "Must call LogShout.configure before creating handlers" unless @validated_config
    @handlers = {}
    configuration[:defaultHandlers].each do |h|
      @handlers[h[:name]] = create_handler(h)
    end
    configuration[:extraHandlers].each do |name, h|
      @handlers[name] = create_handler(h)
    end
    @handlers.freeze
  end

  def self.create_handler(handler)
    LogShout::IORactor.new(handler: handler) # must respond_to?(:write)
  end

  def self.validate_config(config)
    extra_handlers = config.fetch(:extraHandlers, {}).each_with_object({}) do |(name, config), obj|
      if name === :stdout || name === :stderr
        raise LogShoutError, "Cannot override built-in handler: #{name}"
      end
      handler = case config[:type]
      when "memory"
        LogHandler.new(name: name.to_sym, type: LogDestination::MEMORY)
      when "file"
        if !config[:path]
          raise LogShoutError, "File handler #{name} requires a path"
        end
        LogHandler.new(name: name.to_sym, type: LogDestination::FILE, destination: config[:path])
      when "stdout"
        LogHandler.new(name: name.to_sym, type: LogDestination::STD_OUT)
      when "stderr"
        LogHandler.new(name: name.to_sym, type: LogDestination::STD_ERR)
      else
        raise LogShoutError, "Unknown handler type: #{config[:type]}"
      end
      obj[name.to_sym] = handler
    end
    default_handler_names = config.fetch(:defaultHandlers, ["stdout"])
    default_handlers = default_handler_names.map do |name|
      BUILTIN_HANDLERS[name.to_sym] || extra_handlers[name.to_sym] || (raise LogShoutError, "Unknown handler: #{name}")
    end
    default_level = config.fetch(:defaultLevel, "INFO")

    loggers = config.fetch(:loggers, {}).each_with_object({}) do |(name, config), obj|
      level = config.fetch(:level, default_level)
      handlers = config.fetch(:handlers, default_handler_names).map do |name|
        BUILTIN_HANDLERS[name.to_sym] || extra_handlers[name.to_sym] || (raise LogShoutError, "Unknown handler: #{name}")
      end
      obj[name] = LogConfig.new(level: level, handlers: handlers)
    end

    LogConfigFile.new(
      defaultLevel: config.fetch(:defaultLevel, "INFO"),
      defaultHandlers: default_handlers,
      extraHandlers: extra_handlers,
      loggers: loggers
    )
  end

  def self.get_handler(name)
    @handlers[name]
  end

  def self.get_handlers_for(logger_name)
    config = configuration[:loggers].fetch(
      logger_name.to_sym,
      {
        level: configuration[:defaultLevel],
        handlers: configuration[:defaultHandlers]
      }
    )
    config[:handlers].map do |h|
      get_handler(h[:name])
    end
  end

  def self.flush
    return unless @handlers
    @handlers.each_value do |handler|
      handler.flush
    end
  end

  def self.close_handlers
    return unless @handlers
    @handlers.each_value do |handler|
      handler.close
    end
  end

  def self.get_level_for_name(name)
    configuration[:loggers].fetch(
      name.to_sym,
      {
        level: configuration[:defaultLevel],
        handlers: configuration[:defaultHandlers]
      }
    )[:level]
  end

  def self.get_logger(name)
    if (logger = @loggers[name])
      return logger
    end

    config = configuration[:loggers].fetch(
      name,
      {
        level: configuration[:defaultLevel],
        handlers: configuration[:defaultHandlers]
      }
    )

    handlers = config[:handlers].map do |h|
      get_handler(h[:name])
    end

    @loggers[name] = ::Logger.new(LogShout::MultiIO.new(handlers),
      level: ::Logger.const_get(config[:level].upcase),
      progname: name.to_s,
      formatter: LogShout::Formatters::Default.new)
  end

  def self.configuration
    @validated_config || DEFAULT_CONFIG.serialize.freeze
  end

  def self.config_file_path
    @config_file_path
  end

  def self.reset!
    @config_file_path = nil
    @validated_config = nil
    @loggers = {}
  end
end

LogShout.configure

at_exit do
  LogShout.close_handlers
end
