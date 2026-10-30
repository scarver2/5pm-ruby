require "spec_helper"
require "open3"
require "tmpdir"
require "fileutils"
require "digest"

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
      File.write(File.join(directory, "mcp/lib/five_pm/mcp/version.rb"), 'VERSION = "0.2.0"')
      File.write(File.join(directory, "lib/five_pm/version.rb"), 'VERSION = "0.2.0"')
      File.write(File.join(directory, "CHANGELOG.md"), "## 0.2.0 — 2026-10-29\n")
      run_git(directory, "init", "-q")
      run_git(directory, "config", "user.name", "Synthetic Tester")
      run_git(directory, "config", "user.email", "synthetic@example.com")
      run_git(directory, "add", ".")
      run_git(directory, "commit", "-qm", "synthetic evidence base")
      evidence_commit = run_git(directory, "rev-parse", "HEAD")
      evidence = { version: "0.2.0", evidence_commit: evidence_commit, disposable_tenant: true,
                   result: "passed", contract_verified: true, read_operations_verified: true,
                   mutation_operations_verified: true }
      File.write(File.join(directory, "docs/live-validation.json"), JSON.generate(evidence))
      run_git(directory, "add", ".")
      run_git(directory, "commit", "-qm", "synthetic completed validation")
      candidate = run_git(directory, "rev-parse", "HEAD")
      run_git(directory, "update-ref", "refs/remotes/origin/master", candidate)
      script = File.join(directory, "bin/release-check")
      output, status = Open3.capture2e("bash", script, "0.2.0", candidate)
      expect(status).to be_success
      expect(output).to include("explicit publication approval is still required")
      expect(run_git(directory, "tag", "--list")).to eq("")
      run_git(directory, "tag", "v0.2.0", candidate)
      tag_script = File.join(directory, "bin/verify-release-tag")
      output, status = Open3.capture2e({ "GITHUB_REF" => "refs/tags/v0.2.0" }, "bash", tag_script)
      expect(status).to be_success, output
      expect(output).to include("Verified v0.2.0 at #{candidate}")
      _, status = Open3.capture2e({ "GITHUB_REF" => "refs/heads/master" }, "bash", tag_script)
      expect(status).not_to be_success
      run_git(directory, "tag", "-d", "v0.2.0")
      File.write(File.join(directory, "dirty.txt"), "uncommitted")
      _, status = Open3.capture2e("bash", script, "0.2.0", candidate)
      expect(status).not_to be_success
      File.delete(File.join(directory, "dirty.txt"))
      run_git(directory, "tag", "v0.2.0", evidence_commit)
      output, status = Open3.capture2e("bash", script, "0.2.0", candidate)
      expect(status).not_to be_success
      expect(output).to include("tag points elsewhere")
      run_git(directory, "tag", "-d", "v0.2.0")
      File.write(File.join(directory, "lib/five_pm/changed.rb"), "# Untested runtime change\n")
      run_git(directory, "add", ".")
      run_git(directory, "commit", "-qm", "untested change after validation")
      changed_candidate = run_git(directory, "rev-parse", "HEAD")
      run_git(directory, "update-ref", "refs/remotes/origin/master", changed_candidate)
      output, status = Open3.capture2e("bash", script, "0.2.0", changed_candidate)
      expect(status).not_to be_success
      expect(output).to include("differs from the live-validated commit")
    end
  end

  it "accepts only the pinned complete recorded baseline for 0.1.0 without claiming fresh live checks" do
    Dir.mktmpdir("five-pm-recorded-release-") do |directory|
      %w[bin/support lib/five_pm mcp/lib/five_pm/mcp docs].each do |path|
        FileUtils.mkdir_p(File.join(directory, path))
      end
      %w[_lib.sh release-check support/release_check.rb].each do |path|
        FileUtils.cp(File.join(__dir__, "../bin", path), File.join(directory, "bin", path))
      end
      %w[lib/five_pm/version.rb mcp/lib/five_pm/mcp/version.rb].each do |path|
        File.write(File.join(directory, path), 'VERSION = "0.1.0"')
      end
      File.write(File.join(directory, "CHANGELOG.md"), "## 0.1.0 — 2026-10-30\n")
      File.write(File.join(directory, "lib/five_pm/operations.json"), JSON.generate("tasks" => { "getList" => {} }))
      run_git(directory, "init", "-q")
      run_git(directory, "config", "user.name", "Synthetic Tester")
      run_git(directory, "config", "user.email", "synthetic@example.com")
      run_git(directory, "add", ".")
      run_git(directory, "commit", "-qm", "recorded source")
      historical = run_git(directory, "rev-parse", "HEAD")
      reports = %w[live_reads live_mutations live_attachments_users live_cleanup].map do |check|
        { check: check, passed: true, report: { result: "passed", cleanup_verified: true }, diagnostics: [] }
      end
      report = { version: "0.1.0", evidence_commit: historical, worktree_dirty: true,
                 result: "passed", disposable_tenant: true, mutations_enabled: true, release_evidence: false,
                 api_operations_verified: ["tasks.getList"], api_operations_missing: [], reports: reports }
      bytes = JSON.generate(report)
      policy = { version: "0.1.0", mode: "recorded_baseline", report: "docs/live-validation-report.json",
                 report_sha256: Digest::SHA256.hexdigest(bytes), fresh_candidate_live_validation: false }
      File.write(File.join(directory, policy[:report]), bytes)
      policy_path = File.join(directory, "docs/recorded-release-baseline.json")
      File.write(policy_path, JSON.generate(policy))
      # Candidate code may differ from historical source under this reviewed release decision.
      File.write(File.join(directory, "lib/five_pm/new.rb"), "# Offline-verified candidate change\n")
      script = File.join(directory, "bin/release-check")
      commit_candidate = lambda do
        run_git(directory, "add", ".")
        run_git(directory, "commit", "-qm", "candidate")
        candidate = run_git(directory, "rev-parse", "HEAD")
        run_git(directory, "update-ref", "refs/remotes/origin/master", candidate)
        candidate
      end
      output, status = Open3.capture2e("bash", script, "0.1.0", commit_candidate.call)
      expect(status).to be_success, output
      expect(output).to include("no fresh candidate live validation is claimed")
      expect(run_git(directory, "tag", "--list")).to eq("")
      report[:api_operations_verified] = []
      File.write(File.join(directory, policy[:report]), JSON.generate(report))
      output, status = Open3.capture2e("bash", script, "0.1.0", commit_candidate.call)
      expect(status).not_to be_success
      expect(output).to include("digest mismatch")
      policy[:report_sha256] = Digest::SHA256.hexdigest(JSON.generate(report))
      File.write(policy_path, JSON.generate(policy))
      output, status = Open3.capture2e("bash", script, "0.1.0", commit_candidate.call)
      expect(status).not_to be_success
      expect(output).to include("does not cover candidate operations")
      report[:api_operations_verified] = ["tasks.getList"]
      reports.last[:report][:cleanup_verified] = false
      bytes = JSON.generate(report)
      File.write(File.join(directory, policy[:report]), bytes)
      policy[:report_sha256] = Digest::SHA256.hexdigest(bytes)
      File.write(policy_path, JSON.generate(policy))
      _, status = Open3.capture2e("bash", script, "0.1.0", commit_candidate.call)
      expect(status).not_to be_success
    end
  end

  it "rejects malformed release coordinates and offers read-only help" do
    script = File.join(__dir__, "../bin/release-check")
    _, status = Open3.capture2e("bash", script, "0.2.0", "HEAD")
    expect(status).not_to be_success
    output, status = Open3.capture2e("bash", script, "--help")
    expect(status).to be_success
    expect(output).to include("never publishes")
  end
end
