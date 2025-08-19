# frozen_string_literal: true

require "rake/testtask"
require "bundler/gem_tasks"

Rake::TestTask.new(:test) do |task|
  task.libs << "test"
  task.pattern = "test/**/test_*.rb"
end

desc "Check Ruby style"
task :lint do
  sh "bundle exec standardrb"
end

task default: [:test, :lint]
