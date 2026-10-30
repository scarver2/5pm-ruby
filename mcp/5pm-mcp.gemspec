require_relative "lib/five_pm/mcp/version"
Gem::Specification.new do |spec|
  spec.name = "5pm-mcp"
  spec.version = FivePM::MCPAdapter::VERSION
  spec.authors = ["Stan Carver II"]
  spec.summary = "Least-privilege MCP adapter for the 5pm SDK"
  spec.homepage = "https://github.com/scarver2/5pm-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"
  spec.files = Dir["lib/**/*.rb", "sig/**/*", "exe/*", "README.md", "LICENSE"].select { |path| File.file?(path) }
  spec.bindir = "exe"
  spec.executables = ["five-pm-mcp"]
  spec.require_paths = ["lib"]
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.add_dependency "5pm", "~> 0.1.0"
  spec.add_dependency "mcp", "~> 1.6.1"
end
