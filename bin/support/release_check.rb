# Read-only checks. This command never tags, pushes, merges or publishes.
require "open3"

if ARGV == ["--help"]
  puts "Usage: bin/release-check VERSION FULL_COMMIT_SHA"
  puts "Checks clean accepted source, package versions, dated changelog and tag consistency; never publishes."
  exit
end
version, commit = ARGV
valid_version = version && /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/.match?(version)
valid_commit = commit && /\A[0-9a-f]{40}\z/.match?(commit)
abort "expected stable version and full commit SHA" unless ARGV.length == 2 && valid_version && valid_commit
Dir.chdir(File.expand_path("../..", __dir__)) do
  git = lambda do |*arguments|
    output, status = Open3.capture2e("git", *arguments)
    abort "release Git check failed (#{arguments.join(' ')}): #{output.strip}" unless status.success?
    output
  end
  abort "checkout must be clean" unless git.call("status", "--porcelain").empty?
  abort "expected an exact commit" unless git.call("rev-parse", "#{commit}^{commit}").strip == commit
  _, accepted = Open3.capture2e("git", "merge-base", "--is-ancestor", commit, "refs/remotes/origin/master")
  unless accepted.success?
    abort "candidate must be included in origin/master; fetch origin and merge the reviewed preparation first"
  end
  source = git.call("show", "#{commit}:lib/five_pm/version.rb")
  abort "version mismatch" unless source.match?(/^\s*VERSION = "#{Regexp.escape(version)}"(?:\.freeze)?\s*$/)
  adapter = git.call("show", "#{commit}:mcp/lib/five_pm/mcp/version.rb")
  abort "MCP version mismatch" unless adapter.match?(/^\s*VERSION = "#{Regexp.escape(version)}"(?:\.freeze)?\s*$/)
  changelog = git.call("show", "#{commit}:CHANGELOG.md")
  abort "missing dated changelog" unless changelog.match?(/^## #{Regexp.escape(version)} — \d{4}-\d{2}-\d{2}$/)
  _, tag_status = Open3.capture2e("git", "show-ref", "--verify", "refs/tags/v#{version}")
  if tag_status.success? && git.call("rev-parse", "refs/tags/v#{version}^{commit}").strip != commit
    abort "existing version tag points elsewhere"
  end
  puts "Verified release candidate #{version} at #{commit}; explicit publication approval is still required."
end
