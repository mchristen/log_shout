# LogShout

Fan-out logging for Ruby using Ractors. LogShout wraps Ruby's `::Logger` to write each log message to multiple destinations (stdout, stderr, files, in-memory) concurrently and safely.

## WARNING

Ractor support in Ruby is EXPERIMENTAL use at your own risk.

## Installation

Requires CRuby 4.0 or newer (`Ractor::Port` and `Ractor#value`).

Add to your Gemfile and bundle:

```ruby
gem "log_shout", "~> 0.1"
```

```bash
bundle install
```

## Quick start

1. Optionally create a `log_shout.yml` alongside your app (or set `LOG_SHOUT_CONFIG_PATH`). If you skip this, LogShout will run with sane defaults (documented below). If you specify `LOG_SHOUT_CONFIG_PATH` and the file does not exist you will get a runtime error.

```yaml
---
defaultLevel: info
defaultHandlers: [stdout]
extraHandlers:
  app_file_log:
    type: file
    path: ./app.log
loggers:
  app:
    level: debug
    handlers: [stdout, app_file_log]
```

2. Use LogShout in your code:

```ruby
require "log_shout"

logger = LogShout.get_logger(:app)
logger.info("Hello from LogShout")
# in your console
# [2025-10-04 10:50:55.514722 #583620/583642] I -- app: Hello from LogShout
```

Tip: include the helper to get class/instance-level loggers.
This will provide access to a logger named after the class via both a class and instance method named logger.

```ruby
module MyModule
  class MyClass
    include LogShout::Helper

    def self.class_method
      logger.debug("my message")
    # [2025-10-04 10:50:55.514722 #583620/583642] D -- MyModule::MyClass: my message
    end

    def method
      logger.debug("my message")
    # [2025-10-04 10:50:55.514722 #583620/583642] D -- MyModule::MyClass: my message
    end
  end
end

```

Tip: Run a job in its own Ractor with a Ractor safe logger
This behavior is similar to the class based helpers but the API is different.

If you have the following class

```ruby
class MyJob
  def self.run(logger, p1, p2)
    logger.debug("some background task #{p1} #{p2}")
    p1+p2
  end
end
```

Then you can run the job as follows.

```ruby
r = LogShout::LoggingRactor.start(target: MyJob, name: :app, args: [1, 4])
# [2025-10-04 10:50:55.514722 #583620/583642] D -- MyJob: some background task 1 4
r.value # 5
```

## Configuration

### Schema

- defaultLevel: info|debug|warn|fatal
- defaultHandlers: [stdout] # array of handler names that every logger inherits by default.
- extraHandlers: map of name -> `{ type: stdout|stderr|file|memory, path?: string }` (file requires path).
- loggers: map of logger name -> `{ level: string, handlers: [names...] }`.

Notes:

- Built-in handlers `stdout` and `stderr` cannot be overridden. eg. you cannot create a **new** handler named `:stdout`

## Using without a config file (defaults)

The configuration file is optional. These are the defaults.

```yaml
---
defaultLevel: INFO
defaultHandlers: [stdout]
extraHandlers: {}
loggers: {}
```

Runtime behavior of default config:

- If you set `LOG_SHOUT_CONFIG_PATH` and that file doesn’t exist, `configure` will raise.
- Any logger name you request (e.g., `get_logger(:anything)`) uses the default level and handlers when not explicitly configured.
- By default only `stdout` is attached; to add `stderr`, `file`, or `memory`, define them in `extraHandlers` and reference by name in a logger’s `handlers`.

Minimal example with defaults (no file present):

```ruby
require "log_shout"
LogShout.get_logger(:any).info("goes to STDOUT at INFO level")
```

## Delivery, failure, and lifecycle

`logger.info` and the other severity methods enqueue messages asynchronously.
Returning from a log call does not mean a destination has written the message.
Each destination processes its queue in order. Ordering across independent
producers or different destinations is not guaranteed.

```ruby
LogShout.flush          # wait for earlier queued writes at every destination
LogShout.close_handlers # drain queues, close destinations, wait for workers
```

`flush` flushes Ruby IO buffers; it does not call `fsync` or guarantee survival
of a crash or power failure. Queues and memory destinations are unbounded:
slow destinations or large volumes can consume significant memory. There is
currently no backpressure, rotation, retry, or delivery guarantee after failure.

Destinations are opened during configuration. If opening or writing fails,
`Ractor::RemoteError` is raised by initialization or the next synchronous
`flush`, `read`, or `close`; its `cause` contains the underlying IO exception.
A failed worker wakes waiting callers. A live worker blocked in operating-system
IO can still block a flush or shutdown; no IO timeout is imposed. Ruby Logger
may report immediate write errors to stderr instead of propagating them, so use
an explicit `LogShout.flush` where delivery needs to be checked.

Calling `logger.close` flushes its shared destinations. Only
`LogShout.close_handlers` closes them, and repeated shutdown is safe. An `at_exit`
hook attempts shutdown and reports failures to stderr without masking an earlier
application exception. For reliable delivery, explicitly stop producers and call
`close_handlers` before exiting.

`LogShout.configure(path: ...)` validates and opens the replacement destinations,
drains and closes the previous handlers, and clears the logger cache. Invalid
configuration or an opening failure preserves the current configuration.
`LogShout.reset!` closes handlers and clears configuration; the next `get_logger`
loads configuration again. Stop and join background jobs before reconfiguring,
resetting, or closing. Discard old logger references and fetch fresh ones after
reconfiguration. Configuration changes are intended for the main Ractor while
producers are stopped; concurrent reconfiguration is unsupported.

String and symbol logger names are equivalent. Use `LoggingRactor.start` to
create loggers inside background Ractors rather than calling the module's global
configuration methods from another Ractor. Join the returned job with `r.value`
before flushing or closing destinations in the main Ractor.

## Architecture: Logger I/O

This shows how log messages flow from your code through Ruby’s `::Logger`, across `MultiIO`, into per-destination Ractors, and finally to underlying IOs.

Key parts:

- `LogShout.get_logger` in [lib/log_shout.rb](lib/log_shout.rb): builds `::Logger` with a custom logdev and default formatter.
- `LogShout::MultiIO` in [lib/log_shout/multi_io.rb](lib/log_shout/multi_io.rb): fan-out logdev that forwards `write/flush/close` to all handlers.
- `LogShout::IORactor` in [lib/log_shout/io_ractor.rb](lib/log_shout/io_ractor.rb): one ractor per handler; owns the actual IO (STDOUT/ERR/File/StringIO).
- `LogShout::LoggingRactor` in [lib/log_shout/logging_ractor.rb](lib/log_shout/logging_ractor.rb): helper to run a job in its own ractor with a ready-to-use logger.
- Default formatter in [lib/log_shout/formatters/default.rb](lib/log_shout/formatters/default.rb).

`LogShout::IORactor` objects are pre-created for all handlers defined. These objects are shared between all loggers that are created. So if you create 20 loggers with the same handler, only one `LogShout::IORactor` will exist, and thus only one Ractor will be created.

### Component view

```mermaid
flowchart LR
  subgraph App
    A["Your code"]
  end

  subgraph LogShout core
    LS["get_logger(name)<br/>/log_shout.rb"]
    L["Logger<br/> stdlib"]
    M["LogShout::MultiIO<br/>/log_shout/multi_io.rb"]
  end

  subgraph "Handlers (per destination)"
    direction TB
    H1["LogShout::IORactor<br/>(stdout)<br/>/log_shout/io_ractor.rb"]
    H2["LogShout::IORactor<br/>(stderr)<br/>/log_shout/io_ractor.rb"]
    H3["LogShout::IORactor<br/>(file)<br/>/log_shout/io_ractor.rb"]
    H4["LogShout::IORactor<br/>(memory)<br/>/log_shout/io_ractor.rb"]
  end

  subgraph "Ractor workers (one per handler)"
    direction TB
    R1["Ractor loop<br/>.for_fd(1)"]
    R2["Ractor loop<br/>.for_fd(2)"]
    R3["Ractor loop<br/>.open(path,'a')"]
    R4["Ractor loop"]
  end

  A -->|"logger = LogShout.get_logger(:name)"| LS
  LS -->|builds| L
  L -->|logdev| M

  M -->|write/flush/close| H1
  M -->|write/flush/close| H2
  M -->|write/flush/close| H3
  M -->|write/flush/close| H4

  H1 -->|"send [:op, ...]"| R1
  H2 -->|"send [:op, ...]"| R2
  H3 -->|"send [:op, ...]"| R3
  H4 -->|"send [:op, ...]"| R4

  R1 --> IO1[(STDOUT)]
  R2 --> IO2[(STDERR)]
  R3 --> IO3[(File)]
  R4 --> IO4[(StringIO)]
```

### Sequence view (write/flush/close)

```mermaid
sequenceDiagram
  participant App
  participant Logger as ::Logger
  participant MultiIO as LogShout::MultiIO
  participant IO as LogShout::IORactor

  App->>Logger: info("msg")
  Logger->>Logger: format -> "s"
  Logger->>MultiIO: write("s")
  loop for each handler
    MultiIO->>IO: write("s")
  end
```

## Dev setup(with nix+direnv)

The flake uses Ruby 4.0 from `nixos-unstable`, including the `Ractor::Port` API
previously used from Ruby nightly. No local Ruby fork is needed. Bundix uses
[the fork required by ruby-nix](https://github.com/inscapist/ruby-nix#global-bundix-installation-optional)
for platform-dependent gems, built with the same Ruby as the project.

```bash
direnv allow
bundix
```

Without Nix, install dependencies with a released Bundler:

```bash
gem install bundler -v 2.7.2
bundle _2.7.2_ install
```

Run the tests and style checks with `bundle exec rake`; build with
`bundle exec rake build`. Run `ruby script/check_package.rb` to install the
built gem into a temporary gem home and check it through Bundler without the
development dependencies. That check downloads runtime dependencies.

See [CHANGELOG.md](CHANGELOG.md) and [RELEASING.md](RELEASING.md) for release status
and publishing instructions. Licensed under the [MIT License](LICENSE).
