# bin/support/release_prepare.rb
# frozen_string_literal: true

# Prepares a release on a new local branch. It never commits, pushes, tags or
# publishes; review the changes and open a pull request from the branch.
require "date"
require "open3"
require_relative "release_preparation"

USAGE = "Usage: bin/release-prepare VERSION [--date YYYY-MM-DD]"
FILES = {
  core: "lib/five_pm/version.rb", adapter: "mcp/lib/five_pm/mcp/version.rb", changelog: "CHANGELOG.md",
  gemspec: "mcp/5pm-mcp.gemspec", lock: "Gemfile.lock", minimum_lock: "gemfiles/mcp_minimum.gemfile.lock",
  readme: "README.md", adapter_readme: "mcp/README.md"
}.freeze

if ARGV == ["--help"]
  puts USAGE
  puts "Bumps both gem versions, dates the Unreleased changelog entries, updates lockfiles and install docs"
  puts "on a new VERSION branch. It never commits, pushes, tags or publishes."
  exit
end
arguments = ARGV.dup
date = Date.today.iso8601
if (index = arguments.index("--date"))
  date = arguments.delete_at(index + 1).to_s
  arguments.delete_at(index)
end
abort USAGE unless arguments.length == 1
version = arguments.first

Dir.chdir(File.expand_path("../..", __dir__)) do
  git = lambda do |*command|
    output, status = Open3.capture2e("git", *command)
    abort "release preparation Git check failed (#{command.join(' ')}): #{output.strip}" unless status.success?
    output.strip
  end
  abort "checkout must be clean" unless git.call("status", "--porcelain").empty?
  abort "start from master" unless git.call("rev-parse", "--abbrev-ref", "HEAD") == "master"
  git.call("fetch", "--quiet", "origin", "master:refs/remotes/origin/master", "--tags")
  abort "master must match origin/master; pull first" unless
    git.call("rev-parse", "HEAD") == git.call("rev-parse", "refs/remotes/origin/master")
  abort "tag v#{version} already exists" unless git.call("tag", "--list", "v#{version}").empty?

  sources = FILES.transform_values { |path| File.read(path) }
  current = sources.fetch(:core)[/VERSION = "([^"]+)"/, 1]
  abort "core and adapter versions differ" unless sources.fetch(:adapter)[/VERSION = "([^"]+)"/, 1] == current
  begin
    ReleasePreparation.check_version!(current, version)
    updated = {
      core: ReleasePreparation.version_source(sources.fetch(:core), current, version),
      adapter: ReleasePreparation.version_source(sources.fetch(:adapter), current, version),
      changelog: ReleasePreparation.changelog(sources.fetch(:changelog), version, date),
      gemspec: ReleasePreparation.adapter_gemspec(sources.fetch(:gemspec), version),
      lock: ReleasePreparation.lockfile(sources.fetch(:lock), current, version),
      minimum_lock: ReleasePreparation.lockfile(sources.fetch(:minimum_lock), current, version),
      readme: ReleasePreparation.install_docs(sources.fetch(:readme), current, version),
      adapter_readme: ReleasePreparation.install_docs(sources.fetch(:adapter_readme), current, version)
    }
  rescue ReleasePreparation::Error => e
    abort "release preparation failed: #{e.message}"
  end

  git.call("switch", "--quiet", "--create", version)
  updated.each { |key, text| File.write(FILES.fetch(key), text) unless text == sources.fetch(key) }
  puts "Prepared #{version} (from #{current}), dated #{date}, on branch #{version}:"
  git.call("status", "--short").each_line { |line| puts "  #{line}" }
  puts <<~NEXT
    Next: review the diff, run bin/spec, bin/lint and bin/package-mcp, then commit and open a pull request.
    After it merges, run bin/release-check #{version} MERGE_SHA and dispatch the Release gems workflow.
  NEXT
end
