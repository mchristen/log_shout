# Changelog

## 0.1.0 (unreleased)

Initial release candidate:

- Fan out Ruby Logger messages to stdout, stderr, files, and memory through Ractors.
- Configure named loggers and shared destinations with YAML.
- Provide class and instance logger helpers and background job logging.
- Require Ruby 4.0 or newer for Ractor::Port and Ractor#value.
- Drain and close destinations during reconfiguration, reset, and shutdown.
- Surface destination failures to callers of flush, read, and close.
