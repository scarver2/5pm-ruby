# spec/live_cleanup_ledger_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "support/live_cleanup_ledger"

RSpec.describe LiveCleanupLedger do
  around do |example|
    Dir.mktmpdir("five-pm-ledger-") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:path) { File.join(@directory, "state", "ledger.json") }
  let(:ledger) { described_class.new(path, host: "sandbox.example.invalid") }

  it "persists entries with owner-only permissions and no tenant hostname" do
    ledger.record(:users, 42, suite: "live_users")
    expect(File.stat(path).mode & 0o777).to eq(0o600)
    expect(File.stat(File.dirname(path)).mode & 0o777).to eq(0o700)
    expect(File.read(path)).not_to include("sandbox.example.invalid")
    reopened = described_class.new(path, host: "SANDBOX.example.invalid")
    expect(reopened.pending.map { |entry| entry.values_at("service", "id", "suite") })
      .to eq([%w[users 42 live_users]])
  end

  it "keeps tenants apart and resolves only the confirmed entry" do
    other = described_class.new(path, host: "other.example.invalid")
    ledger.record(:projects, 1, suite: "live_attachments")
    ledger.record(:tasks, 2, suite: "live_attachments")
    ledger.record(:tasks, 2, suite: "live_attachments")
    other.record(:projects, 1, suite: "live_attachments")
    ledger.resolve(:projects, 1)
    expect(ledger.pending.map { |entry| entry["id"] }).to eq(["2"])
    expect(other.pending.map { |entry| entry["id"] }).to eq(["1"])
  end

  it "drains newest first so children are removed before their parents" do
    ledger.record(:projects, 1, suite: "live_attachments")
    ledger.record(:tasks, 2, suite: "live_attachments")
    ledger.record(:activity, 3, suite: "live_attachments")
    removed = []
    ledger.drain! { |service, id| removed << [service, id] }
    expect(removed).to eq([%w[activity 3], %w[tasks 2], %w[projects 1]])
    expect(ledger.pending).to be_empty
  end

  it "retains unconfirmed entries and refuses new work when an earlier cleanup still fails" do
    ledger.record(:users, 42, suite: "live_users")
    ledger.record(:projects, 1, suite: "live_attachments")
    expect do
      ledger.drain! { |service, _id| raise FivePM::APIError, 8 if service == "users" }
    end.to raise_error(FivePM::ProtocolError, "earlier live records still await cleanup")
    expect(ledger.pending.map { |entry| entry.values_at("service", "id") }).to eq([%w[users 42]])
  end

  it "rejects a ledger that other users can read" do
    ledger.record(:users, 42, suite: "live_users")
    File.chmod(0o644, path)
    expect { ledger.pending }.to raise_error(described_class::UnsafeLedgerError, /other users/)
  end

  it "rejects malformed ledgers instead of discarding their entries" do
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "[]", perm: 0o600)
    expect { ledger.pending }.to raise_error(described_class::UnsafeLedgerError, /malformed/)
    expect(File.read(path)).to eq("[]")
  end

  it "defaults outside the repository and refuses paths inside it" do
    root = File.expand_path("..", __dir__)
    expect(described_class.path({}, repository_root: root)).to eq(described_class::DEFAULT_PATH)
    expect(described_class.path({ "FIVE_PM_LIVE_LEDGER" => path }, repository_root: root)).to eq(path)
    [File.join(root, "tmp", "ledger.json"), root].each do |inside|
      expect { described_class.path({ "FIVE_PM_LIVE_LEDGER" => inside }, repository_root: root) }
        .to raise_error(described_class::UnsafeLedgerError, /outside the repository/)
    end
  end
end
