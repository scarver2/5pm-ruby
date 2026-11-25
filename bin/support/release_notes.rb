# bin/support/release_notes.rb
# frozen_string_literal: true

# Prints GitHub release notes for a tagged version from CHANGELOG.md and the
# gemspecs. Read-only; the Release gems workflow posts the result after both
# gems are published.
require "open3"
require "rubygems"

module ReleaseNotes
  class Error < StandardError; end

  REPOSITORY = "https://github.com/scarver2/5pm-ruby"
  SIGNATURE = "—\nStan Carver II\nMade in Texas 🤠\nhttps://stancarver.com\n"

  module_function

  def section(changelog, version)
    heading = changelog.match(/^## #{Regexp.escape(version)} — \d{4}-\d{2}-\d{2}[ \t]*\n/)
    raise Error, "CHANGELOG.md has no dated #{version} section" unless heading

    rest = changelog[heading.end(0)..]
    entries = rest[0...(rest.index(/^## /) || rest.length)].strip
    raise Error, "the #{version} changelog section is empty" if entries.empty?

    entries
  end

  # The newest stable vX.Y.Z tag older than the version, if any.
  def previous_tag(tags, version)
    current = Gem::Version.new(version)
    tags.filter_map { |tag| tag[/\Av(\d+\.\d+\.\d+)\z/, 1] }
        .map { |number| Gem::Version.new(number) }.select { |number| number < current }.max&.then { |v| "v#{v}" }
  end

  def build(changelog:, version:, commit:, previous:, ruby:, adapter_dependencies:, run_url: nil)
    validation = []
    validation << "- [Release workflow run](#{run_url})" if run_url
    validation << "- [Source commit](#{REPOSITORY}/commit/#{commit})"
    validation << "- [Full changelog](#{REPOSITORY}/compare/#{previous}...v#{version})" if previous
    <<~NOTES
      ## Changes

      #{section(changelog, version)}

      ## Published gems

      - [5pm #{version}](https://rubygems.org/gems/5pm/versions/#{version}) — Ruby SDK for the 5pm API v2.
      - [5pm-mcp #{version}](https://rubygems.org/gems/5pm-mcp/versions/#{version}) — MCP adapter; depends on #{adapter_dependencies.map { |dependency| "`#{dependency}`" }.join(' and ')}.

      Both gems require #{ruby} and were published through GitHub Actions trusted publishing.

      ## Validation

      The release workflow ran specs, lint and package smoke checks on every supported Ruby version, and verified the published package bytes against the approved builds.

      #{validation.join("\n")}

      #{SIGNATURE}
    NOTES
  end

  # The gemspec minimum, such as ">= 3.2", as "Ruby 3.2 or newer".
  def ruby_requirement(gemspec)
    minimum = gemspec[/required_ruby_version = ">= ([\d.]+)"/, 1]
    raise Error, "5pm.gemspec has no minimum Ruby version" unless minimum

    "Ruby #{minimum} or newer"
  end

  def adapter_dependencies(gemspec)
    dependencies = gemspec.scan(/add_dependency "([^"]+)", (.+)$/).map do |name, requirements|
      "#{name} #{requirements.scan(/"([^"]+)"/).flatten.join(', ')}"
    end
    raise Error, "mcp/5pm-mcp.gemspec declares no runtime dependencies" if dependencies.empty?

    dependencies
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.first == "--help" || ARGV.empty?
    puts "Usage: bin/release-notes VERSION [--run-url URL]"
    puts "Prints release notes for the existing vVERSION tag from CHANGELOG.md; never publishes."
    exit(ARGV.empty? ? 1 : 0)
  end
  version = ARGV.first
  run_url = ARGV[ARGV.index("--run-url") + 1] if ARGV.include?("--run-url")
  Dir.chdir(File.expand_path("../..", __dir__)) do
    commit, status = Open3.capture2e("git", "rev-parse", "--verify", "refs/tags/v#{version}^{commit}")
    abort "tag v#{version} does not exist" unless status.success?
    commit = commit.strip
    # Read every source from the tagged commit, never the working tree, so the
    # notes always describe exactly what was released.
    tagged = lambda do |path|
      text, shown = Open3.capture2e("git", "show", "#{commit}:#{path}")
      abort "cannot read #{path} at v#{version}" unless shown.success?
      text
    end
    tags, = Open3.capture2("git", "tag", "--list", "v*")
    puts ReleaseNotes.build(changelog: tagged.call("CHANGELOG.md"), version: version, commit: commit,
                            previous: ReleaseNotes.previous_tag(tags.split, version),
                            ruby: ReleaseNotes.ruby_requirement(tagged.call("5pm.gemspec")),
                            adapter_dependencies: ReleaseNotes.adapter_dependencies(tagged.call("mcp/5pm-mcp.gemspec")),
                            run_url: run_url)
  rescue ReleaseNotes::Error => e
    abort "release notes failed: #{e.message}"
  end
end
