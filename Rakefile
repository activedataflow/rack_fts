# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "cucumber/rake/task"

RSpec::Core::RakeTask.new(:spec)

Cucumber::Rake::Task.new(:cucumber) do |t|
  t.cucumber_opts = "--format pretty"
end

task default: [:spec, :cucumber]

desc "Run RSpec tests"
task :test => :spec

desc "Run all tests (RSpec + Cucumber)"
task :test_all => [:spec, :cucumber]

desc "Run console"
task :console do
  require "irb"
  require_relative "lib/rack-fts"
  ARGV.clear
  IRB.start
end
