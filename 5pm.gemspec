require_relative "lib/five_pm/version"
Gem::Specification.new do |spec|
  spec.name = "5pm"
  spec.version = FivePM::VERSION
  spec.authors = ["Stan Carver II"]
  spec.summary = "Ruby SDK for the 5pm API v2"
  spec.homepage = "https://github.com/scarver2/5pm-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*", "sig/**/*.rbs", "docs/**/*", "examples/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md",
                   "SECURITY.md"].select do |path|
    File.file?(path)
  end
  spec.require_paths = ["lib"]
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/master/CHANGELOG.md"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.add_dependency "json", ">= 2.6", "< 4"
  spec.add_dependency "net-http", ">= 0.3", "< 1"
end
