require "bundler"
require "rubygems/package"
require "tmpdir"
require "fileutils"
require "rbconfig"

root = File.expand_path("../..", __dir__)
Dir.chdir(root) do
  abort "core package verification failed" unless system("bash", "bin/package")
  require_relative "../../mcp/lib/five_pm/mcp/version"
  Dir.chdir("mcp") do
    FileUtils.mkdir_p("pkg")
    abort "adapter gem build failed" unless system(RbConfig.ruby, "-S", "gem", "build", "5pm-mcp.gemspec",
                                                   "--strict", "--output", "pkg/5pm-mcp-#{FivePM::MCPAdapter::VERSION}.gem")
  end
  core = Gem::Specification.load("5pm.gemspec")
  abort "MCP leaked into core runtime dependencies" if core.runtime_dependencies.any? { |dep| dep.name == "mcp" }
  adapter = Dir.chdir("mcp") { Gem::Specification.load("5pm-mcp.gemspec") }
  package = Gem::Package.new("mcp/pkg/5pm-mcp-#{adapter.version}.gem")
  unless package.spec.files.sort == adapter.files.sort && package.spec.license == "MIT"
    abort "adapter package inventory or license mismatch"
  end
  abort "missing adapter RBS signatures" unless package.spec.files.include?("sig/five_pm-mcp.rbs")
  abort "missing RBS dependency manifest" unless package.spec.files.include?("sig/manifest.yaml")
  dependency_path = Bundler.load.specs.map(&:base_dir).uniq.join(File::PATH_SEPARATOR)
  Dir.mktmpdir("five-pm-mcp-package-") do |directory|
    environment = { "GEM_HOME" => directory, "GEM_PATH" => dependency_path }
    Bundler.with_unbundled_env do
      ["pkg/5pm-#{core.version}.gem", "mcp/pkg/5pm-mcp-#{adapter.version}.gem"].each do |path|
        installer = "Gem::Installer.at(ARGV.fetch(0), install_dir: ARGV.fetch(1), " \
                    "ignore_dependencies: true, document: []).install"
        unless system(environment, RbConfig.ruby, "-rrubygems/installer", "-e", installer, path, directory)
          abort "isolated package installation failed"
        end
      end
      smoke = <<~CODE
        require "five_pm/mcp"
        %w[5pm 5pm-mcp].each do |name|
          actual = File.realpath(Gem.loaded_specs.fetch(name).full_gem_path)
          abort "package loaded from source checkout" unless actual.start_with?(File.realpath(ARGV.fetch(0)) + File::SEPARATOR)
        end
        server = FivePM::MCPAdapter::Server.new(client: Object.new).server
        result = JSON.parse(server.handle_json(JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list")))
        abort "installed adapter failed protocol smoke test" unless result.fetch("result").fetch("tools").length == 10
        # Resolve by gem name to verify the shipped manifest loads core signatures.
        abort "installed RBS validation failed" unless system(RbConfig.ruby, "-S", "rbs", "-r", "5pm-mcp", "validate")
      CODE
      abort "installed adapter smoke failed" unless system(environment, RbConfig.ruby, "-e", smoke, directory)
    end
  end
  puts "Verified core and standalone MCP packages"
end
