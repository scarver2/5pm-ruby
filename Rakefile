require "rspec/core/rake_task"
require_relative "bin/support/release_tasks"
FivePMReleaseTasks.install(__dir__)
RSpec::Core::RakeTask.new(:spec)
desc "Check locked dependencies support the minimum Ruby version"
task :compatibility do
  require "bundler/setup"
  minimum = Gem::Version.new("3.2.0")
  incompatible = Bundler.load.specs.reject { |spec| spec.required_ruby_version.satisfied_by?(minimum) }
  abort "Dependencies do not support Ruby #{minimum}: #{incompatible.map(&:name).join(', ')}" unless incompatible.empty?
end

desc "Validate core and MCP RBS signatures"
task :signatures do
  ruby "-S", "rbs", "-I", "sig", "-I", "mcp/sig", "validate"
  ruby "-S", "rbs", "-I", "sig", "-I", "mcp/sig", "test", "--target", "FivePM::*",
       RbConfig.ruby, "-Ilib", "-Imcp/lib", "spec/support/rbs_smoke.rb"
end

task default: %i[compatibility signatures spec]
