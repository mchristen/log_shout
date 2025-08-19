# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require "rubygems/package"

# Install into a clean gem home, then boot through Bundler as a consumer would.
# Run without `bundle exec` so no development gems can mask dependencies.
abort "Run with ruby, not bundle exec" if ENV["BUNDLE_GEMFILE"]
root = File.expand_path("..", __dir__)
ruby = RbConfig.ruby
gem_command = File.join(RbConfig::CONFIG.fetch("bindir"), "gem")

def run!(env, *command, **options)
  output, status = Open3.capture2e(env, *command, **options)
  abort "#{command.join(" ")} failed:\n#{output}" unless status.success?
  puts output unless output.empty?
end

Dir.mktmpdir("log-shout-package") do |dir|
  package = File.join(dir, "log_shout.gem")
  run!({}, ruby, gem_command, "build", "log_shout.gemspec", "--output", package, chdir: root)
  spec = Gem::Package.new(package).spec
  %w[LICENSE README.md CHANGELOG.md lib/log_shout.rb].each do |file|
    abort "Missing packaged file: #{file}" unless spec.files.include?(file)
  end
  abort "Missing logger dependency" unless spec.runtime_dependencies.any? { |dep| dep.name == "logger" }
  env = ENV.keys.grep(/\ABUNDLE_/).to_h { |key| [key, nil] }.merge(
    "GEM_HOME" => File.join(dir, "gems"),
    "GEM_PATH" => File.join(dir, "gems"),
    "RUBYOPT" => nil,
    "RUBYLIB" => nil,
    "BUNDLE_PATH" => nil,
    "BUNDLE_GEMFILE" => nil
  )
  run!(env, ruby, gem_command, "install", package, "--no-document")
  File.write(File.join(dir, "Gemfile"), "source 'https://rubygems.org'\ngem 'log_shout', '= #{spec.version}'\n")
  smoke = <<~RUBY
    require "bundler/setup"
    require "log_shout"
    handler = LogShout::IORactor.new(handler: {type: :memory})
    handler.write("installed gem works")
    handler.flush
    abort "missing output" unless handler.read == "installed gem works"
    handler.close
    LogShout.close_handlers
    puts "Installed package passed consumer smoke test"
  RUBY
  run!(env, ruby, "-e", smoke, chdir: dir)
end
