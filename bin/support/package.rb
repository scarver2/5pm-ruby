require "tmpdir"
require "fileutils"
require "rbconfig"
require "bundler"

root = File.expand_path("../..", __dir__)
Dir.chdir(root) do
  require_relative "../../lib/five_pm/version"
  FileUtils.mkdir_p("pkg")
  abort "gem build failed" unless system(RbConfig.ruby, "-S", "gem", "build", "5pm.gemspec", "--strict",
                                         "--output", "pkg/5pm-#{FivePM::VERSION}.gem")
  path = "pkg/5pm-#{FivePM::VERSION}.gem"
  abort "package inspection failed" unless system(RbConfig.ruby, "bin/verify-package.rb", path)
  Dir.mktmpdir("five-pm-package-") do |directory|
    dependency_path = Bundler.load.specs.map(&:base_dir).uniq.join(File::PATH_SEPARATOR)
    environment = { "GEM_HOME" => directory, "GEM_PATH" => dependency_path }
    installer = "Gem::Installer.at(ARGV.fetch(0), install_dir: ARGV.fetch(1), " \
                "ignore_dependencies: true, document: []).install"
    Bundler.with_unbundled_env do
      unless system(environment, RbConfig.ruby, "-rrubygems/installer", "-e", installer, path, directory)
        abort "isolated package installation failed"
      end
    end
    smoke = <<~CODE
      gem "5pm", ARGV.fetch(1)
      require "five_pm"
      abort "version mismatch" unless FivePM::VERSION == ARGV.fetch(1)
      model = FivePM::Models::Task.new({"id" => "42", "hidden" => "false", "future" => true})
      abort "mapping failed" unless model.id == 42 && model.hidden == false && model.raw["future"] == true
      abort "wrong load path" unless $LOADED_FEATURES.any? { |path| path.end_with?("/five_pm.rb") && File.realpath(path).start_with?(File.realpath(ARGV.fetch(0)) + File::SEPARATOR) }
    CODE
    Bundler.with_unbundled_env do
      valid = system(environment, RbConfig.ruby, "-e", smoke, directory, FivePM::VERSION)
      abort "isolated package smoke test failed" unless valid
      unless system(environment, RbConfig.ruby, "-S", "rbs", "-r", "5pm", "validate")
        abort "packaged core RBS validation failed"
      end
    end
  end
  puts "Verified #{path}"
end
