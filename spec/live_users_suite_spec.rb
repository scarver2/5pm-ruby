# spec/live_users_suite_spec.rb
# frozen_string_literal: true

require "json"
require "rbconfig"
require "spec_helper"
require "tmpdir"
require_relative "support/live_subprocess"

# Replays the 2026-10-30 failure offline: users.add succeeds, users.update and
# users.remove return API code 8, and cleanup cannot finish.
RSpec.describe "live User suite cleanup", :aggregate_failures do
  around do |example|
    Dir.mktmpdir("five-pm-live-users-") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:root) { File.expand_path("..", __dir__) }
  let(:tenant_path) { File.join(@directory, "tenant.json") }
  let(:ledger_path) { File.join(@directory, "state", "ledger.json") }

  def run_suite(deny_writes:)
    environment = { "FIVE_PM_SANDBOX" => "1", "FIVE_PM_HOST" => "offline-check.5pmweb.com",
                    "FIVE_PM_SANDBOX_HOST" => "offline-check.5pmweb.com", "FIVE_PM_ALLOW_MUTATIONS" => "1",
                    "FIVE_PM_LIVE_USER_ADMIN" => "1", "FIVE_PM_LOGIN" => "synthetic", "FIVE_PM_PASSWORD" => "synthetic",
                    "FIVE_PM_LIVE_LEDGER" => ledger_path, "FIVE_PM_FAKE_TENANT" => tenant_path,
                    "FIVE_PM_FAKE_DENY_USER_WRITES" => deny_writes ? "1" : "0" }
    output, errors, status = LiveSubprocess.capture(
      environment, RbConfig.ruby, "-I#{root}/lib", "-r", "#{root}/spec/support/live_fake_tenant",
      "#{root}/spec/support/live_users.rb", timeout: 60
    )
    [output, errors.lines.map { |line| JSON.parse(line) }, status]
  end

  def tenant_users
    JSON.parse(File.read(tenant_path)).fetch("users")
  end

  def ledger_entries
    JSON.parse(File.read(ledger_path)).fetch("entries")
  end

  it "retains a leaked User, refuses new writes until it is removed, then cleans up" do
    _, diagnostics, status = run_suite(deny_writes: true)
    expect(status).not_to be_success
    expect(diagnostics.first).to include("stage" => "users.update", "api_code" => 8)
    expect(diagnostics).to include("result" => "cleanup_failed", "service" => "users", "retained_in_ledger" => true)
    expect(tenant_users.length).to eq(1)
    expect(ledger_entries.map { |entry| entry.values_at("service", "id", "suite") })
      .to eq([["users", tenant_users.first.fetch("id"), "live_users"]])
    expect(File.read(ledger_path)).not_to include("offline-check.5pmweb.com")

    _, diagnostics, status = run_suite(deny_writes: true)
    expect(status).not_to be_success
    expect(diagnostics.first).to include("stage" => "ledger.pending_cleanup")
    expect(tenant_users.length).to eq(1)
    expect(ledger_entries.length).to eq(1)

    output, diagnostics, status = run_suite(deny_writes: false)
    expect(status).to be_success
    expect(diagnostics).to be_empty
    expect(JSON.parse(output)).to include("result" => "passed",
                                          "checks" => %w[users.preflight users.create users.update users.get
                                                         users.delete])
    expect(tenant_users).to be_empty
    expect(ledger_entries).to be_empty
  end
end
