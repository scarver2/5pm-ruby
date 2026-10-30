# Read-only checks. This command never tags, pushes, merges or publishes.
require "open3"
require "json"
require "digest"

if ARGV == ["--help"]
  puts "Usage: bin/release-check VERSION FULL_COMMIT_SHA"
  puts "Checks a clean, accepted master commit and version-specific validation evidence; never publishes."
  exit
end
version, commit = ARGV
valid_version = version && /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/.match?(version)
valid_commit = commit && /\A[0-9a-f]{40}\z/.match?(commit)
abort "expected stable version and full commit SHA" unless ARGV.length == 2 && valid_version && valid_commit
Dir.chdir(File.expand_path("../..", __dir__)) do
  git = lambda do |*arguments|
    output, status = Open3.capture2e("git", *arguments)
    abort "release Git check failed" unless status.success?
    output
  end
  abort "checkout must be clean" unless git.call("status", "--porcelain").empty?
  abort "expected an exact commit" unless git.call("rev-parse", "#{commit}^{commit}").strip == commit
  git.call("merge-base", "--is-ancestor", commit, "refs/remotes/origin/master")
  source = git.call("show", "#{commit}:lib/five_pm/version.rb")
  abort "version mismatch" unless source.match?(/^\s*VERSION = "#{Regexp.escape(version)}"(?:\.freeze)?\s*$/)
  adapter = git.call("show", "#{commit}:mcp/lib/five_pm/mcp/version.rb")
  abort "MCP version mismatch" unless adapter.match?(/^\s*VERSION = "#{Regexp.escape(version)}"(?:\.freeze)?\s*$/)
  changelog = git.call("show", "#{commit}:CHANGELOG.md")
  abort "missing dated changelog" unless changelog.match?(/^## #{Regexp.escape(version)} — \d{4}-\d{2}-\d{2}$/)
  if version == "0.1.0"
    begin
      policy = JSON.parse(git.call("show", "#{commit}:docs/recorded-release-baseline.json"))
      report_bytes = git.call("show", "#{commit}:docs/live-validation-report.json")
      report = JSON.parse(report_bytes)
      operations = JSON.parse(git.call("show", "#{commit}:lib/five_pm/operations.json"))
    rescue JSON::ParserError
      abort "recorded baseline is not valid JSON"
    end
    unless policy["version"] == version && policy["mode"] == "recorded_baseline" &&
           policy["report"] == "docs/live-validation-report.json" &&
           policy["fresh_candidate_live_validation"] == false &&
           policy["report_sha256"] == Digest::SHA256.hexdigest(report_bytes)
      abort "recorded baseline policy or report digest mismatch"
    end
    inventory = operations.flat_map do |service, methods|
      methods.keys.map { |operation| "#{service}.#{operation}" }
    end.sort
    reports = report["reports"]
    required_reports = %w[live_attachments_users live_cleanup live_mutations live_reads]
    complete_reports = reports.is_a?(Array) && reports.map { |item| item["check"] }.sort == required_reports
    successful_reports = complete_reports && reports.all? do |item|
      item["passed"] == true && item.dig("report", "result") == "passed" && item["diagnostics"] == []
    end
    cleanup_verified = successful_reports &&
                       reports.find { |item| item["check"] == "live_cleanup" }.dig("report", "cleanup_verified") == true
    unless report["version"] == version && report["result"] == "passed" &&
           report["disposable_tenant"] == true && report["mutations_enabled"] == true &&
           report["release_evidence"] == false && report["api_operations_verified"] == inventory &&
           report["api_operations_missing"] == [] && cleanup_verified &&
           /\A[0-9a-f]{40}\z/.match?(report.fetch("evidence_commit", ""))
      abort "recorded baseline is incomplete or does not cover candidate operations"
    end
    git.call("merge-base", "--is-ancestor", report.fetch("evidence_commit"), commit)
    puts "Using recorded 0.1.0 baseline; no fresh candidate live validation is claimed."
  else
    begin
      evidence = JSON.parse(git.call("show", "#{commit}:docs/live-validation.json"))
    rescue JSON::ParserError
      abort "live-validation evidence is not valid JSON"
    end
    unless evidence["version"] == version && evidence["disposable_tenant"] == true &&
           evidence["result"] == "passed" && evidence["contract_verified"] == true &&
           evidence["read_operations_verified"] == true && evidence["mutation_operations_verified"] == true &&
           evidence["evidence_commit"].is_a?(String) &&
           /\A[0-9a-f]{40}\z/.match?(evidence["evidence_commit"])
      abort "live-validation evidence is incomplete"
    end
    git.call("merge-base", "--is-ancestor", evidence.fetch("evidence_commit"), commit)
    changed = git.call("diff", "--name-only", evidence.fetch("evidence_commit"), commit).lines.map(&:strip)
    unless changed.all? { |path| path == "docs/live-validation.json" }
      abort "candidate differs from the live-validated commit; validate the changed code again"
    end
  end
  _, tag_status = Open3.capture2e("git", "show-ref", "--verify", "refs/tags/v#{version}")
  if tag_status.success? && git.call("rev-parse", "refs/tags/v#{version}^{commit}").strip != commit
    abort "existing version tag points elsewhere"
  end
  puts "Verified release candidate #{version} at #{commit}; explicit publication approval is still required."
end
