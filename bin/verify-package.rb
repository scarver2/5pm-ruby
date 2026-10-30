#!/usr/bin/env ruby
require "rubygems/package"

Dir.chdir(File.expand_path("..", __dir__)) do
  package = Gem::Package.new(File.expand_path(ARGV.fetch(0)))
  expected = Gem::Specification.load("5pm.gemspec")
  unless package.spec.name == expected.name && package.spec.version == expected.version
    abort "package metadata mismatch"
  end
  unless package.spec.files.sort == expected.files.sort && package.contents.sort == expected.files.sort
    abort "package file mismatch"
  end
  abort "license mismatch" unless package.spec.license == "MIT" && package.spec.files.include?("LICENSE")
  %w[sig/five_pm.rbs sig/models.rbs].each do |signature|
    abort "missing core RBS signatures" unless package.spec.files.include?(signature)
  end
  if package.spec.files.any? { |file| file.match?(%r{(^|/)(spec|vendor|coverage|\.env)(/|$)}) }
    abort "unexpected private or development files in package"
  end
  puts "Verified #{package.contents.length} packaged files"
end
