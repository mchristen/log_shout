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

  class HandlerErrors < LogShoutError
    attr_reader :errors

    def initialize(errors)
      @errors = errors.flat_map { |error| error.is_a?(HandlerErrors) ? error.errors : [error] }.freeze
      details = @errors.map do |error|
        detail = "#{error.class}: #{error.message}"
        detail += " (#{error.cause.class}: #{error.cause.message})" if error.cause
        detail
      end
      super("#{@errors.length} handler failures: #{details.join("; ")}")
    end

    def self.raise_if_any(errors)
      raise errors.first if errors.length == 1
      raise new(errors) unless errors.empty?
    end
  end

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

  # Keep keyword-only constructors for the public configuration structs.

  LogHandler = Struct.new(:name, :type, :destination, keyword_init: true) do # standard:disable Style/RedundantStructKeywordInit
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

  LogConfig = Struct.new(:level, :handlers, keyword_init: true) do # standard:disable Style/RedundantStructKeywordInit
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

  LogConfigFile = Struct.new(:loggers, :extraHandlers, :defaultLevel, :defaultHandlers, keyword_init: true) do # standard:disable Style/RedundantStructKeywordInit
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
    config_file_path = requested_path || default_path
    config = if File.exist?(config_file_path)
      begin
        validate_config(YAML.load_file(config_file_path, symbolize_names: true))
      rescue Psych::SyntaxError => e
        raise LogShoutError, "Failed to parse YAML configuration file at #{config_file_path}: #{e.message}"
      end
    elsif requested_path
      raise LogShoutError, "Configuration file not found at #{config_file_path}"
    else
      DEFAULT_CONFIG
    end
    validated_config = config.serialize.freeze
    handlers = build_handlers(validated_config)
    begin
      close_handlers
    rescue => e
      errors = e.is_a?(HandlerErrors) ? e.errors : [e]
      if errors.all? { |error| error.is_a?(Ractor::RemoteError) }
        # Every old destination has been closed; report each failed worker.
        errors.each do |error|
          warn "LogShout replaced failed handlers: #{error.cause.class}: #{error.cause.message}"
        end
      else
        handlers.each_value(&:close)
        raise
      end
    end
    @config_file_path = config_file_path
    @validated_config = validated_config
    @handlers = handlers.freeze
    @loggers = {}
    @config_file_path
  end

  def self.build_handlers(config)
    handlers = {}
    definitions = config[:defaultHandlers] + config[:extraHandlers].values +
      config[:loggers].values.flat_map { |logger| logger[:handlers] }
    definitions.uniq { |handler| handler[:name] }.each do |handler|
      handlers[handler[:name]] = create_handler(handler)
    end
    handlers
  rescue
    handlers.each_value(&:close)
    raise
  end
  private_class_method :build_handlers

  def self.create_handler(handler)
    LogShout::IORactor.new(handler: handler) # must respond_to?(:write)
  end

  def self.validate_config(config)
    raise LogShoutError, "Configuration must be a mapping" unless config.is_a?(Hash)
    [:extraHandlers, :loggers].each do |key|
      raise LogShoutError, "#{key} must be a mapping" unless config.fetch(key, {}).is_a?(Hash)
    end
    default_level = config.fetch(:defaultLevel, "INFO")
    validate_level(default_level)
    default_handler_names = config.fetch(:defaultHandlers, ["stdout"])
    raise LogShoutError, "defaultHandlers must be an array" unless default_handler_names.is_a?(Array)
    extra_handlers = config.fetch(:extraHandlers, {}).each_with_object({}) do |(name, config), obj|
      name = configuration_name(name, "handler")
      if name === :stdout || name === :stderr
        raise LogShoutError, "Cannot override built-in handler: #{name}"
      end
      raise LogShoutError, "Handler #{name} must be a mapping" unless config.is_a?(Hash)
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
    default_handlers = default_handler_names.map do |name|
      name = configuration_name(name, "handler")
      BUILTIN_HANDLERS[name] || extra_handlers[name] || (raise LogShoutError, "Unknown handler: #{name}")
    end

    loggers = config.fetch(:loggers, {}).each_with_object({}) do |(name, config), obj|
      name = configuration_name(name, "logger")
      raise LogShoutError, "Logger #{name} must be a mapping" unless config.is_a?(Hash)
      level = config.fetch(:level, default_level)
      validate_level(level)
      handler_names = config.fetch(:handlers, default_handler_names)
      raise LogShoutError, "Logger #{name} handlers must be an array" unless handler_names.is_a?(Array)
      handlers = handler_names.map do |name|
        name = configuration_name(name, "handler")
        BUILTIN_HANDLERS[name] || extra_handlers[name] || (raise LogShoutError, "Unknown handler: #{name}")
      end
      obj[name.to_sym] = LogConfig.new(level: level, handlers: handlers)
    end

    LogConfigFile.new(
      defaultLevel: config.fetch(:defaultLevel, "INFO"),
      defaultHandlers: default_handlers,
      extraHandlers: extra_handlers,
      loggers: loggers
    )
  end

  def self.validate_level(level)
    unless level.is_a?(String) && %w[DEBUG INFO WARN ERROR FATAL UNKNOWN].include?(level.upcase)
      raise LogShoutError, "Invalid log level: #{level.inspect}"
    end
  end
  private_class_method :validate_level

  def self.configuration_name(name, kind)
    unless name.is_a?(String) || name.is_a?(Symbol)
      raise LogShoutError, "Invalid #{kind} name: #{name.inspect}; expected a string or symbol"
    end
    name.to_sym
  end
  private_class_method :configuration_name

  def self.get_handler(name)
    @handlers[name]
  end

  def self.get_handlers_for(logger_name)
    configure unless @handlers
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
    MultiIO.new(@handlers.values).flush
  end

  def self.close_handlers
    errors = []
    (@handlers || {}).each_value do |handler|
      handler.close
    rescue => e
      errors << e
    end
    HandlerErrors.raise_if_any(errors)
    nil
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
    configure unless @handlers
    name = name.to_sym
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
    close_handlers
    @handlers = nil
    @config_file_path = nil
    @validated_config = nil
    @loggers = {}
  end
end

LogShout.configure

at_exit do
  LogShout.close_handlers
rescue => e
  warn "LogShout shutdown failed: #{e.class}: #{e.message}"
end
