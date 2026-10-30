require "open3"
root = File.expand_path("../..", __dir__)
Dir.chdir(root) do
  ref = ENV.fetch("RELEASE_TAG_REF") { ENV.fetch("GITHUB_REF", "") }
  unless %r{\Arefs/tags/v(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z}.match?(ref)
    abort "expected a stable vVERSION tag"
  end
  commit, status = Open3.capture2("git", "rev-parse", "HEAD")
  abort "cannot resolve checkout" unless status.success?
  commit = commit.strip
  version = ref.delete_prefix("refs/tags/v")
  abort "release preflight failed" unless system("bash", File.join(root, "bin/release-check"), version, commit)
  tag, status = Open3.capture2("git", "rev-parse", "--verify", "#{ref}^{commit}")
  abort "tag must match publishing checkout" unless status.success? && tag.strip == commit
  puts "Verified v#{version} at #{commit}"
end
