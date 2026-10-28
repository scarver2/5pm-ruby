require "rspec/core/rake_task"
RSpec::Core::RakeTask.new(:spec)
desc "Check locked dependencies support the minimum Ruby version"
task :compatibility do
  require "bundler/setup"
  minimum = Gem::Version.new("3.2.0")
  incompatible = Bundler.load.specs.reject { |spec| spec.required_ruby_version.satisfied_by?(minimum) }
  abort "Dependencies do not support Ruby #{minimum}: #{incompatible.map(&:name).join(', ')}" unless incompatible.empty?
end

task default: %i[compatibility spec]
