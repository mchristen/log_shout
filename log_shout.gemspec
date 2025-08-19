# frozen_string_literal: true

require_relative "lib/log_shout/version"

Gem::Specification.new do |spec|
  spec.name = "log_shout"
  spec.version = LogShout::VERSION
  spec.authors = ["Matt Christen"]
  spec.email = ["oss@christen.tech"]
  spec.summary = "Ruby loggers with flexibility."
  spec.description = "Easy to configure ruby loggers. Multi-destination and configuration levels."
  spec.homepage = "https://github.com/mchristen/log_shout"
  spec.license = "MIT"
  # Ractor::Port and Ractor#value were introduced in Ruby 4.0.
  spec.required_ruby_version = ">= 4.0.0"

  spec.metadata = {
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "documentation_uri" => "#{spec.homepage}#readme",
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir.glob(%w[
    lib/**/*.rb
    bin/*
    *.md
    LICENSE
  ])
  spec.bindir = "bin"
  spec.executables = []
  spec.require_paths = ["lib"]

  spec.add_dependency "logger", "~> 1.7"

  spec.add_development_dependency "standard", "~> 1.53"
  spec.add_development_dependency "standard-performance", "~> 1.6"
  spec.add_development_dependency "ruby-lsp", "~> 0.23"
  spec.add_development_dependency "minitest", "~> 5.26", ">= 5.26.1"
  spec.add_development_dependency "rake", "~> 13.1"
  spec.add_development_dependency "bundler-audit", "~> 0.9"
  spec.add_development_dependency "debug", "~> 1.11"
end
