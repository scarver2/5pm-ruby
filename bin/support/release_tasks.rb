require "rake"
require "bundler/gem_helper"
require "open3"

module FivePMReleaseTasks
  extend Rake::DSL

  def self.install(base)
    Bundler::GemHelper.install_tasks(dir: base)
    # The release-gem action invokes `rake release`. Only an already-approved,
    # pre-tagged exact candidate may reach Bundler's RubyGems push task.
    root = File.expand_path("../..", __dir__)
    Rake::Task["release:guard_clean"].enhance do
      unless ENV["GITHUB_ACTIONS"] == "true" && ENV["GITHUB_REPOSITORY"] == "scarver2/5pm-ruby" &&
             ENV["FIVE_PM_RELEASE_APPROVED"] == "true"
        abort "publication requires the protected GitHub release workflow"
      end
      version = ENV.fetch("RELEASE_VERSION")
      commit = ENV.fetch("RELEASE_COMMIT")
      spec = Bundler::GemHelper.gemspec
      unless spec.version.to_s == version && %w[5pm 5pm-mcp].include?(spec.name)
        abort "publishing gem must match the approved package/version"
      end
      abort "publishing checkout must equal approved commit" unless Open3.capture2("git", "rev-parse",
                                                                                   "HEAD").first.strip == commit
      unless system("bash", File.join(root, "bin/release-check"), version, commit)
        abort "release candidate verification failed"
      end
      tag, status = Open3.capture2("git", "rev-parse", "--verify", "refs/tags/v#{version}^{commit}")
      abort "approved tag must already exist at the approved commit" unless status.success? && tag.strip == commit
    end

    # Tag creation is isolated in the approved Contents-write job. Publishing must
    # never create/move a tag or push a branch, including when a tag is missing.
    Rake::Task["release:source_control_push"].clear
    task "release:source_control_push"
    Rake::Task["release:rubygem_push"].enhance(["release:guard_clean"])
    Rake::Task["release"].clear_comments
    Rake::Task["release"].add_description("Publish an approved, pre-tagged gem through the protected GitHub workflow")
  end
end
