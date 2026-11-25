# spec/live_mutations_suite_spec.rb
# frozen_string_literal: true

require "json"
require "rbconfig"
require "spec_helper"
require "tmpdir"
require_relative "support/live_subprocess"

# Runs the core/MCP mutation suite offline against the fake tenant. The fake
# refuses every project group update, so each run stops right after its first
# create and exercises only the cleanup and ledger paths.
RSpec.describe "live mutation suite cleanup", :aggregate_failures do
  around do |example|
    Dir.mktmpdir("five-pm-live-mutations-") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:root) { File.expand_path("..", __dir__) }
  let(:tenant_path) { File.join(@directory, "tenant.json") }
  let(:ledger_path) { File.join(@directory, "state", "ledger.json") }

  def run_suite(deny_remove:)
    environment = { "FIVE_PM_SANDBOX" => "1", "FIVE_PM_HOST" => "offline-check.5pmweb.com",
                    "FIVE_PM_SANDBOX_HOST" => "offline-check.5pmweb.com", "FIVE_PM_ALLOW_MUTATIONS" => "1",
                    "FIVE_PM_LOGIN" => "synthetic", "FIVE_PM_PASSWORD" => "synthetic",
                    "FIVE_PM_LIVE_LEDGER" => ledger_path, "FIVE_PM_FAKE_TENANT" => tenant_path,
                    "FIVE_PM_FAKE_DENY_GROUP_REMOVE" => deny_remove ? "1" : "0" }
    _, errors, status = LiveSubprocess.capture(
      environment, RbConfig.ruby, "-I#{root}/lib", "-I#{root}/mcp/lib", "-r", "#{root}/spec/support/live_fake_tenant",
      "#{root}/spec/support/live_mutations.rb", timeout: 60
    )
    [errors.lines.map { |line| JSON.parse(line) }, status]
  end

  def tenant_groups
    JSON.parse(File.read(tenant_path)).fetch("groups")
  end

  def ledger_entries
    JSON.parse(File.read(ledger_path)).fetch("entries")
  end

  it "keeps an undeleted record in the ledger, creates nothing until it is gone, then cleans up" do
    diagnostics, status = run_suite(deny_remove: true)
    expect(status).not_to be_success
    expect(diagnostics.first).to include("stage" => "project_groups.update", "api_code" => 8,
                                         "passed" => ["project_groups.create"])
    expect(diagnostics).to include("result" => "cleanup_failed", "service" => "project_groups",
                                   "retained_in_ledger" => true)
    expect(tenant_groups.length).to eq(1)
    expect(ledger_entries.map { |entry| entry.values_at("service", "id", "suite") })
      .to eq([["project_groups", tenant_groups.first.fetch("id"), "live_mutations"]])
    expect(File.read(ledger_path)).not_to include("offline-check.5pmweb.com")

    diagnostics, status = run_suite(deny_remove: true)
    expect(status).not_to be_success
    expect(diagnostics.first).to include("stage" => "ledger.pending_cleanup", "passed" => [])
    expect(tenant_groups.length).to eq(1)
    expect(ledger_entries.length).to eq(1)

    diagnostics, status = run_suite(deny_remove: false)
    expect(status).not_to be_success
    expect(diagnostics.first).to include("stage" => "project_groups.update", "passed" => ["project_groups.create"])
    expect(diagnostics.drop(1)).to be_empty
    expect(tenant_groups).to be_empty
    expect(ledger_entries).to be_empty
  end
end
