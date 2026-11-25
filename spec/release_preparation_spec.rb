# spec/release_preparation_spec.rb
# frozen_string_literal: true

require "fileutils"
require "open3"
require "spec_helper"
require "tmpdir"
require_relative "../bin/support/release_preparation"

RSpec.describe ReleasePreparation do
  let(:root) { File.expand_path("..", __dir__) }
  # The next minor version, so these examples keep working after each release.
  let(:target) { FivePM::VERSION.split(".").then { |major, minor, _| "#{major}.#{minor.to_i + 1}.0" } }

  def read(path)
    File.read(File.join(root, path))
  end

  describe "text transforms" do
    it "bumps a version constant exactly once" do
      expect(described_class.version_source(%(  VERSION = "0.2.1".freeze\n), "0.2.1", "0.3.0"))
        .to eq(%(  VERSION = "0.3.0".freeze\n))
      expect { described_class.version_source(%(VERSION = "0.2.0"\n), "0.2.1", "0.3.0") }
        .to raise_error(described_class::Error, /exactly one version constant/)
    end

    it "accepts only a stable, greater version" do
      expect { described_class.check_version!("0.2.1", "0.2.2") }.not_to raise_error
      ["0.2.1", "0.2.0", "0.3", "0.3.0.rc1", "v0.3.0"].each do |version|
        expect { described_class.check_version!("0.2.1", version) }.to raise_error(described_class::Error)
      end
    end

    it "moves Unreleased entries under a dated version heading" do
      changelog = "# Changelog\n\n## Unreleased\n\n- Fix a thing.\n\n## 0.2.1 — 2026-11-25\n\n- Old.\n"
      expect(described_class.changelog(changelog, "0.2.2", "2026-12-01"))
        .to eq("# Changelog\n\n## 0.2.2 — 2026-12-01\n\n- Fix a thing.\n\n## 0.2.1 — 2026-11-25\n\n- Old.\n")
    end

    it "refuses a changelog with nothing to release, a bad date or an existing section" do
      empty = "# Changelog\n\n## Unreleased\n\n## 0.2.1 — 2026-11-25\n\n- Old.\n"
      expect { described_class.changelog(empty, "0.2.2", "2026-12-01") }.to raise_error(/no entries/)
      expect { described_class.changelog("# Changelog\n\n## 0.2.1 — 2026-11-25\n", "0.2.2", "2026-12-01") }
        .to raise_error(/no ## Unreleased/)
      %w[12/01/2026 2026-02-31 2026-13-01 2026-00-10].each do |date|
        expect { described_class.changelog("## Unreleased\n\n- New.\n", "0.2.2", date) }.to raise_error(/date/)
      end
      expect { described_class.changelog("## Unreleased\n\n- New.\n\n## 0.2.2 — x\n", "0.2.2", "2026-12-01") }
        .to raise_error(/already has/)
    end

    it "keeps the adapter on the core's minor series" do
      expect(described_class.core_requirement("1.4.2")).to eq("~> 1.4.0")
      gemspec = read("mcp/5pm-mcp.gemspec")
      updated = described_class.adapter_gemspec(gemspec, target)
      expect(updated).to include(%(spec.add_dependency "5pm", "#{described_class.core_requirement(target)}"))
      expect(updated).to include('spec.add_dependency "mcp", ">= 1.6.1"')
    end

    it "updates both path gems and the core requirement in each lockfile" do
      %w[Gemfile.lock gemfiles/mcp_minimum.gemfile.lock].each do |path|
        updated = described_class.lockfile(read(path), FivePM::VERSION, target)
        expect(updated.scan(/^\s+5pm \(#{Regexp.escape(target)}\)$/).length).to eq(2)
        expect(updated.scan(/^\s+5pm-mcp \(#{Regexp.escape(target)}\)$/).length).to eq(2)
        expect(updated).to include("      5pm (#{described_class.core_requirement(target)})")
        expect(updated).not_to match(/^\s+5pm(?:-mcp)? \(#{Regexp.escape(FivePM::VERSION)}\)$/)
      end
      expect { described_class.lockfile("GEM\n", "0.2.1", target) }.to raise_error(/does not list 5pm/)
    end

    it "updates install instructions but leaves historical mentions" do
      readme = described_class.install_docs(read("README.md"), FivePM::VERSION, target)
      expect(readme).to include("gem install 5pm --version #{target}", %(gem "5pm", "~> #{target}"),
                                "/versions/#{target}", "**#{target}**", "tree/v#{target}")
      expect(readme).not_to include("--version #{FivePM::VERSION}")
      adapter = described_class.install_docs(read("mcp/README.md"), FivePM::VERSION, target)
      expect(adapter).to include("gem install 5pm-mcp --version #{target}", "[#{target} is published")
      expect(adapter).to include("Available since 0.2.0")
      expect { described_class.install_docs("No versions here.\n", "0.2.1", target) }.to raise_error(/no install/)
    end
  end

  it "keeps the install docs on the current version, so a release cannot skip them" do
    [read("README.md"), read("mcp/README.md")].each do |document|
      document.scan(/--version (\S+)/).flatten.each { |version| expect(version).to eq(FivePM::VERSION) }
    end
  end

  describe "bin/release-prepare" do
    files = %w[lib/five_pm/version.rb mcp/lib/five_pm/mcp/version.rb CHANGELOG.md mcp/5pm-mcp.gemspec Gemfile.lock
               gemfiles/mcp_minimum.gemfile.lock README.md mcp/README.md]
    scripts = %w[_lib.sh release-prepare support/release_prepare.rb support/release_preparation.rb]

    def git(directory, *arguments)
      output, status = Open3.capture2e("git", "-C", directory, *arguments)
      raise "fixture Git failed: #{output}" unless status.success?

      output.strip
    end

    def prepare(directory, *arguments)
      Open3.capture2e("bash", File.join(directory, "bin/release-prepare"), *arguments)
    end

    around do |example|
      Dir.mktmpdir("five-pm-prepare-") do |directory|
        @repository = File.join(directory, "work")
        files.each do |path|
          FileUtils.mkdir_p(File.dirname(File.join(@repository, path)))
          FileUtils.cp(File.join(root, path), File.join(@repository, path))
        end
        FileUtils.mkdir_p(File.join(@repository, "bin/support"))
        scripts.each { |path| FileUtils.cp(File.join(root, "bin", path), File.join(@repository, "bin", path)) }
        changelog = File.join(@repository, "CHANGELOG.md")
        # Guarantee releasable entries whatever the real changelog holds today.
        unless File.read(changelog).include?("## Unreleased")
          File.write(changelog,
                     File.read(changelog).sub("# Changelog\n\n", "# Changelog\n\n## Unreleased\n\n- Fix.\n\n"))
        end
        git(directory, "init", "-q", "--bare", "origin.git")
        git(@repository, "init", "-q", "-b", "master")
        git(@repository, "config", "user.name", "Synthetic Tester")
        git(@repository, "config", "user.email", "synthetic@example.com")
        git(@repository, "add", ".")
        git(@repository, "commit", "-qm", "synthetic base")
        git(@repository, "remote", "add", "origin", File.join(directory, "origin.git"))
        git(@repository, "push", "-q", "origin", "master")
        example.run
      end
    end

    it "prepares every release file on a new branch without committing, tagging or pushing" do
      output, status = prepare(@repository, target, "--date", "2026-12-01")
      expect(status).to be_success, output
      expect(git(@repository, "rev-parse", "--abbrev-ref", "HEAD")).to eq(target)
      expect(git(@repository, "status", "--short").lines.map { |line| line.split.last }).to match_array(files)
      expect(File.read(File.join(@repository, "lib/five_pm/version.rb"))).to include(%(VERSION = "#{target}"))
      expect(File.read(File.join(@repository, "mcp/lib/five_pm/mcp/version.rb"))).to include(%(VERSION = "#{target}"))
      expect(File.read(File.join(@repository, "CHANGELOG.md"))).to include("## #{target} — 2026-12-01")
      expect(File.read(File.join(@repository, "CHANGELOG.md"))).not_to include("## Unreleased")
      expect(git(@repository, "tag", "--list")).to be_empty
      expect(git(@repository, "log", "--oneline").lines.length).to eq(1)
      expect(git(@repository, "ls-remote", "--heads", "origin")).not_to include(target)
      expect(output).to include("bin/release-check #{target} MERGE_SHA")
    end

    it "refuses unsafe starting points without changing anything" do
      File.write(File.join(@repository, "README.md"), "dirty\n", mode: "a")
      output, status = prepare(@repository, target)
      expect(status).not_to be_success
      expect(output).to include("checkout must be clean")
      git(@repository, "checkout", "--", "README.md")

      git(@repository, "tag", "v#{target}")
      output, status = prepare(@repository, target)
      expect(output).to include("tag v#{target} already exists")
      expect(status).not_to be_success
      git(@repository, "tag", "-d", "v#{target}")

      output, status = prepare(@repository, FivePM::VERSION)
      expect(status).not_to be_success
      expect(output).to include("must be greater")

      git(@repository, "switch", "-q", "-c", "feature")
      output, status = prepare(@repository, target)
      expect(output).to include("start from master")
      expect(status).not_to be_success
      expect(git(@repository, "branch", "--list", target)).to be_empty
      expect(git(@repository, "status", "--porcelain")).to be_empty
    end
  end
end
