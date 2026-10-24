# Changelog

## 0.1.1 (2026-10-24)

- Continue delivering messages to healthy destinations when another destination fails.
- Attempt every destination during flush and shutdown; report multiple failures through
  `LogShout::HandlerErrors#errors`, preserving the original exception for a single failure.
- Recover from failed workers when installing a replacement configuration, reporting
  every old worker failure to stderr.
- Initialize configuration when starting a logging job after `reset!`.
- Accept symbol names when starting logging Ractors.
- Report invalid configuration handler and logger names as `LogShoutError`.

## 0.1.0 (2026-10-24)

Initial release:

- Fan out Ruby Logger messages to stdout, stderr, files, and memory through Ractors.
- Configure named loggers and shared destinations with YAML.
- Provide class and instance logger helpers and background job logging.
- Require Ruby 4.0 or newer for Ractor::Port and Ractor#value.
- Drain and close destinations during reconfiguration, reset, and shutdown.
- Surface destination failures to callers of flush, read, and close.
