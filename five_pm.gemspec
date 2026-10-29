require_relative "lib/five_pm/version"
Gem::Specification.new do |spec|
  spec.name = "five_pm"
  spec.version = FivePM::VERSION
  spec.authors = ["Stan Carver II"]
  spec.summary = "Ruby SDK for the 5pm API v2"
  spec.homepage = "https://github.com/scarver2/5pm-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*", "docs/**/*", "README.md", "LICENSE", "CHANGELOG.md", "SECURITY.md"]
  spec.require_paths = ["lib"]
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.add_dependency "json", ">= 2.6", "< 3"
  spec.add_dependency "net-http", ">= 0.3", "< 1"
end
