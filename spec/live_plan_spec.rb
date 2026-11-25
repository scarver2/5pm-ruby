# spec/live_plan_spec.rb
# frozen_string_literal: true

require "rbconfig"
require "spec_helper"
require_relative "support/live_plan"
require_relative "support/live_subprocess"

RSpec.describe LivePlan do
  def result(suite, passed: true)
    { check: suite, passed: passed, diagnostics: [] }
  end

  it "runs only reads without mutations" do
    expect(described_class.suites(mutations: false, user_admin: true)).to eq(%w[live_reads])
    expect(described_class.excluded_operations(mutations: false, user_admin: false)).to be_empty
  end

  it "keeps attachment qualification separate from the Administrator-only User suite" do
    expect(described_class.suites(mutations: true, user_admin: false))
      .to eq(%w[live_reads live_mutations live_attachments live_cleanup])
    expect(described_class.suites(mutations: true, user_admin: true))
      .to eq(%w[live_reads live_mutations live_attachments live_users live_cleanup])
  end

  it "excludes User write operations from the inventory only when the User suite is not enabled" do
    expect(described_class.excluded_operations(mutations: true, user_admin: false))
      .to eq(%w[users.add users.remove users.update])
    expect(described_class.excluded_operations(mutations: true, user_admin: true)).to be_empty
    inventory = JSON.parse(File.read(File.expand_path("../lib/five_pm/operations.json", __dir__)))
                    .flat_map { |service, methods| methods.keys.map { |operation| "#{service}.#{operation}" } }
    expect(described_class::USER_ADMIN_OPERATIONS - inventory).to be_empty
  end

  it "skips later write suites after the first failure but still scans for leftovers" do
    suites = described_class.suites(mutations: true, user_admin: true)
    ran = []
    reports = described_class.run(suites) do |suite|
      ran << suite
      result(suite, passed: suite != "live_mutations")
    end
    expect(ran).to eq(%w[live_reads live_mutations live_cleanup])
    skipped = reports.select { |report| report[:skipped] }
    expect(skipped.map { |report| report[:check] }).to eq(%w[live_attachments live_users])
    expect(skipped).to all(include(passed: false, skipped_after: "live_mutations"))
  end

  it "stops all write suites when the read suite fails" do
    ran = []
    described_class.run(described_class.suites(mutations: true, user_admin: false)) do |suite|
      ran << suite
      result(suite, passed: suite != "live_reads")
    end
    expect(ran).to eq(%w[live_reads live_cleanup])
  end

  it "runs every suite when all pass" do
    suites = described_class.suites(mutations: true, user_admin: true)
    reports = described_class.run(suites) { |suite| result(suite) }
    expect(reports.map { |report| report[:check] }).to eq(suites)
    expect(reports).to all(include(passed: true))
  end

  it "refuses to start the User suite without the Administrator opt-in, before any API call" do
    environment = { "FIVE_PM_SANDBOX" => "1", "FIVE_PM_HOST" => "sandbox.invalid",
                    "FIVE_PM_SANDBOX_HOST" => "sandbox.invalid", "FIVE_PM_ALLOW_MUTATIONS" => "1",
                    "FIVE_PM_LIVE_USER_ADMIN" => nil }
    script = File.expand_path("support/live_users.rb", __dir__)
    _, errors, status = LiveSubprocess.capture(environment, RbConfig.ruby, script, timeout: 30)
    expect(status).not_to be_success
    expect(errors).to include("FIVE_PM_LIVE_USER_ADMIN=1")
  end
end
