require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"

RSpec.describe "read-only release preflight" do
  def run_git(directory, *arguments)
    output, status = Open3.capture2e("git", "-C", directory, *arguments)
    raise "fixture Git failed" unless status.success?

    output.strip
  end

  it "accepts only a clean accepted commit with dated version and explicit live evidence, without publishing" do
    Dir.mktmpdir("five-pm-release-test-") do |directory|
      FileUtils.mkdir_p(File.join(directory, "bin/support"))
      %w[_lib.sh support/release_check.rb verify-release-tag support/verify_release_tag.rb].each do |path|
        FileUtils.cp(File.join(__dir__, "../bin", path), File.join(directory, "bin", path))
      end
      FileUtils.cp(File.join(__dir__, "../bin/release-check"), File.join(directory, "bin/release-check"))
      FileUtils.mkdir_p(File.join(directory, "lib/five_pm"))
      FileUtils.mkdir_p(File.join(directory, "docs"))
      FileUtils.mkdir_p(File.join(directory, "mcp/lib/five_pm/mcp"))
      File.write(File.join(directory, "mcp/lib/five_pm/mcp/version.rb"), 'VERSION = "0.1.0"')
      File.write(File.join(directory, "lib/five_pm/version.rb"), 'VERSION = "0.1.0"')
      File.write(File.join(directory, "CHANGELOG.md"), "## 0.1.0 — 2026-10-29\n")
      run_git(directory, "init", "-q")
      run_git(directory, "config", "user.name", "Synthetic Tester")
      run_git(directory, "config", "user.email", "synthetic@example.com")
      run_git(directory, "add", ".")
      run_git(directory, "commit", "-qm", "synthetic evidence base")
      evidence_commit = run_git(directory, "rev-parse", "HEAD")
      evidence = { version: "0.1.0", evidence_commit: evidence_commit, disposable_tenant: true,
                   result: "passed", contract_verified: true, read_operations_verified: true,
                   mutation_operations_verified: true }
      File.write(File.join(directory, "docs/live-validation.json"), JSON.generate(evidence))
      run_git(directory, "add", ".")
      run_git(directory, "commit", "-qm", "synthetic completed validation")
      candidate = run_git(directory, "rev-parse", "HEAD")
      run_git(directory, "update-ref", "refs/remotes/origin/master", candidate)
      script = File.join(directory, "bin/release-check")
      output, status = Open3.capture2e("bash", script, "0.1.0", candidate)
      expect(status).to be_success
      expect(output).to include("explicit publication approval is still required")
      expect(run_git(directory, "tag", "--list")).to eq("")
      run_git(directory, "tag", "v0.1.0", candidate)
      tag_script = File.join(directory, "bin/verify-release-tag")
      output, status = Open3.capture2e({ "GITHUB_REF" => "refs/tags/v0.1.0" }, "bash", tag_script)
      expect(status).to be_success, output
      expect(output).to include("Verified v0.1.0 at #{candidate}")
      _, status = Open3.capture2e({ "GITHUB_REF" => "refs/heads/master" }, "bash", tag_script)
      expect(status).not_to be_success
      run_git(directory, "tag", "-d", "v0.1.0")
      File.write(File.join(directory, "dirty.txt"), "uncommitted")
      _, status = Open3.capture2e("bash", script, "0.1.0", candidate)
      expect(status).not_to be_success
      File.delete(File.join(directory, "dirty.txt"))
      run_git(directory, "tag", "v0.1.0", evidence_commit)
      output, status = Open3.capture2e("bash", script, "0.1.0", candidate)
      expect(status).not_to be_success
      expect(output).to include("tag points elsewhere")
      run_git(directory, "tag", "-d", "v0.1.0")
      File.write(File.join(directory, "lib/five_pm/changed.rb"), "# Untested runtime change\n")
      run_git(directory, "add", ".")
      run_git(directory, "commit", "-qm", "untested change after validation")
      changed_candidate = run_git(directory, "rev-parse", "HEAD")
      run_git(directory, "update-ref", "refs/remotes/origin/master", changed_candidate)
      output, status = Open3.capture2e("bash", script, "0.1.0", changed_candidate)
      expect(status).not_to be_success
      expect(output).to include("differs from the live-validated commit")
    end
  end

  it "rejects malformed release coordinates and offers read-only help" do
    script = File.join(__dir__, "../bin/release-check")
    _, status = Open3.capture2e("bash", script, "0.1.0", "HEAD")
    expect(status).not_to be_success
    output, status = Open3.capture2e("bash", script, "--help")
    expect(status).to be_success
    expect(output).to include("never publishes")
  end
end
