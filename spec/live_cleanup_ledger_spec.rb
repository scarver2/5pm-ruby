# spec/live_cleanup_ledger_spec.rb
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "spec_helper"
require "tmpdir"
require_relative "support/live_cleanup_ledger"

RSpec.describe LiveCleanupLedger do
  around do |example|
    Dir.mktmpdir("five-pm-ledger-") do |directory|
      # Canonical path, so tests see the same directory the ledger resolves.
      @directory = File.realpath(directory)
      example.run
    end
  end

  let(:root) { File.expand_path("..", __dir__) }
  let(:state) { File.join(@directory, "state") }
  let(:path) { File.join(state, "ledger.json") }
  let(:ledger) { described_class.new(path, host: "sandbox.example.invalid") }

  def unsafe(pattern)
    raise_error(described_class::UnsafeLedgerError, pattern)
  end

  describe "entries" do
    it "persists entries with owner-only permissions and no tenant hostname" do
      ledger.record(:users, 42, suite: "live_users")
      expect(File.stat(path).mode & 0o777).to eq(0o600)
      expect(File.stat("#{path}.lock").mode & 0o777).to eq(0o600)
      expect(File.stat(state).mode & 0o777).to eq(0o700)
      expect(File.read(path)).not_to include("sandbox.example.invalid")
      expect(Dir.children(state)).to contain_exactly("ledger.json", "ledger.json.lock")
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
      ledger.drain!(suite: "live_attachments") { |service, id| removed << [service, id] }
      expect(removed).to eq([%w[activity 3], %w[tasks 2], %w[projects 1]])
      expect(ledger.pending).to be_empty
    end

    it "drains only its own suite, so a leaked User does not block attachment checks" do
      ledger.record(:users, 42, suite: "live_users")
      ledger.record(:projects, 1, suite: "live_attachments")
      removed = []
      ledger.drain!(suite: "live_attachments") { |service, id| removed << [service, id] }
      expect(removed).to eq([%w[projects 1]])
      expect(ledger.pending.map { |entry| entry.values_at("service", "id") }).to eq([%w[users 42]])
    end

    it "retains unconfirmed entries and refuses new work when an earlier cleanup still fails" do
      ledger.record(:users, 42, suite: "live_users")
      ledger.record(:users, 43, suite: "live_users")
      expect do
        ledger.drain!(suite: "live_users") { |_service, id| raise FivePM::APIError, 8 if id == "42" }
      end.to raise_error(FivePM::ProtocolError, "earlier live records still await cleanup")
      expect(ledger.pending.map { |entry| entry.values_at("service", "id") }).to eq([%w[users 42]])
    end

    it "stops draining at once when the ledger becomes unsafe instead of counting it as a failed deletion" do
      ledger.record(:projects, 1, suite: "live_attachments")
      ledger.record(:tasks, 2, suite: "live_attachments")
      removed = []
      expect do
        ledger.drain!(suite: "live_attachments") do |service, id|
          removed << [service, id]
          File.chmod(0o644, path)
        end
      end.to unsafe(/readable only by you/)
      expect(removed).to eq([%w[tasks 2]])
      File.chmod(0o600, path)
      expect(ledger.pending.map { |entry| entry["id"] }).to eq(%w[1 2])
    end

    it "stops on unexpected callback errors instead of counting them as failed deletions" do
      ledger.record(:projects, 1, suite: "live_attachments")
      ledger.record(:tasks, 2, suite: "live_attachments")
      calls = 0
      expect do
        ledger.drain!(suite: "live_attachments") do |_service, _id|
          calls += 1
          raise NoMethodError, "harness bug"
        end
      end.to raise_error(NoMethodError, "harness bug")
      expect(calls).to eq(1)
      expect(ledger.pending.length).to eq(2)
    end

    it "refuses an unsafe ledger raised from the deletion callback without continuing" do
      ledger.record(:projects, 1, suite: "live_attachments")
      ledger.record(:tasks, 2, suite: "live_attachments")
      calls = 0
      expect do
        ledger.drain!(suite: "live_attachments") do |_service, _id|
          calls += 1
          raise described_class::UnsafeLedgerError, "unsafe"
        end
      end.to unsafe(/unsafe/)
      expect(calls).to eq(1)
    end

    it "rejects malformed ledgers instead of discarding their entries" do
      Dir.mkdir(state, 0o700)
      ["[]", "{not json"].each do |content|
        File.write(path, content, perm: 0o600)
        expect { ledger.record(:users, 1, suite: "live_users") }.to unsafe(/malformed/)
        expect(File.read(path)).to eq(content)
      end
    end
  end

  describe "document validation" do
    let(:tenant) { Digest::SHA256.hexdigest("sandbox.example.invalid") }
    let(:valid_entry) do
      { "tenant" => tenant, "service" => "users", "id" => "42", "suite" => "live_users",
        "recorded_at" => "2026-11-25T00:00:00Z" }
    end

    def write_document(document)
      FileUtils.mkdir_p(state, mode: 0o700)
      File.write(path, JSON.generate(document), perm: 0o600)
      File.read(path)
    end

    def expect_refused_without_mutation(document)
      before = write_document(document)
      yielded = []
      %w[live_users live_attachments].each do |suite|
        expect { ledger.drain!(suite: suite) { |*entry| yielded << entry } }
          .to unsafe(/malformed|invalid|version|duplicate/)
      end
      expect { ledger.record(:projects, 7, suite: "live_attachments") }.to unsafe(/malformed|invalid|version|duplicate/)
      expect { ledger.resolve(:users, 42) }.to unsafe(/malformed|invalid|version|duplicate/)
      expect(yielded).to be_empty
      expect(File.read(path)).to eq(before)
    end

    it "accepts a well-formed document" do
      write_document("version" => 1, "entries" => [valid_entry])
      expect(ledger.pending(suite: "live_users")).to eq([valid_entry])
    end

    it "refuses an entry with a missing suite instead of silently skipping its cleanup" do
      expect_refused_without_mutation("version" => 1, "entries" => [valid_entry.except("suite")])
    end

    it "refuses a service outside its suite's allowlist, so attachments never delete Users" do
      expect_refused_without_mutation("version" => 1, "entries" => [valid_entry.merge("suite" => "live_attachments")])
      expect_refused_without_mutation("version" => 1, "entries" => [valid_entry.merge("service" => "projects")])
      expect_refused_without_mutation("version" => 1, "entries" => [valid_entry.merge("suite" => "live_mutations")])
    end

    it "refuses invalid identifiers, tenants and metadata" do
      ["0", "-1", "abc", "42; drop", "", 42].each do |id|
        expect_refused_without_mutation("version" => 1, "entries" => [valid_entry.merge("id" => id)])
      end
      expect_refused_without_mutation("version" => 1, "entries" => [valid_entry.merge("tenant" => "sandbox")])
      expect_refused_without_mutation("version" => 1, "entries" => [valid_entry.merge("recorded_at" => "yesterday")])
      expect_refused_without_mutation("version" => 1, "entries" => [valid_entry.merge("extra" => "x")])
      expect_refused_without_mutation("version" => 1, "entries" => [valid_entry, valid_entry])
    end

    it "refuses duplicate JSON keys instead of keeping only the last value" do
      entry = JSON.generate(valid_entry)
      [%({"version":1,"entries":[],"entries":[#{entry}]}),
       %({"version":1,"entries":[#{entry.sub('"id":"42"', '"id":"42","id":"43"')}]})].each do |content|
        Dir.mkdir(state, 0o700) unless File.directory?(state)
        File.write(path, content, perm: 0o600)
        yielded = []
        expect { ledger.drain!(suite: "live_users") { |*item| yielded << item } }
          .to unsafe(/malformed|duplicate/)
        expect { ledger.record(:users, 44, suite: "live_users") }.to unsafe(/malformed|duplicate/)
        expect(yielded).to be_empty
        expect(File.read(path)).to eq(content)
      end
    end

    it "refuses unsupported or missing versions" do
      [2, "1", nil].each do |version|
        expect_refused_without_mutation("version" => version, "entries" => [valid_entry])
      end
      expect_refused_without_mutation("entries" => [valid_entry])
    end

    it "refuses to record a service outside the suite's allowlist" do
      expect { ledger.record(:users, 42, suite: "live_attachments") }.to unsafe(/invalid entry/)
      expect { ledger.pending(suite: "live_mutations") }.to raise_error(ArgumentError)
      expect(File.exist?(path)).to be(false)
    end
  end

  describe "storage safety" do
    it "fails closed when the platform cannot open files without following symlinks" do
      stub_const("LiveCleanupLedger::NOFOLLOW", nil)
      expect { ledger.record(:users, 42, suite: "live_users") }.to unsafe(/O_NOFOLLOW/)
      expect(File.exist?(state)).to be(false)
    end

    it "rejects a ledger or lock that other users can read" do
      ledger.record(:users, 42, suite: "live_users")
      File.chmod(0o644, path)
      expect { ledger.pending }.to unsafe(/readable only by you/)
      File.chmod(0o600, path)
      File.chmod(0o644, "#{path}.lock")
      expect { ledger.pending }.to unsafe(/lock must be a regular file/)
    end

    it "rejects an existing ledger directory with group or other access without changing it" do
      [0o755, 0o777].each do |mode|
        FileUtils.rm_rf(state)
        Dir.mkdir(state)
        File.chmod(mode, state)
        expect { ledger.record(:users, 42, suite: "live_users") }.to unsafe(/mode 0700/)
        expect(File.stat(state).mode & 0o777).to eq(mode)
        expect(Dir.children(state)).to be_empty
      end
    end

    it "rejects a ledger symlinked to an outside file and leaves the target untouched" do
      Dir.mkdir(state, 0o700)
      target = File.join(@directory, "outside.json")
      File.write(target, '{"version":1,"entries":[]}', perm: 0o600)
      File.symlink(target, path)
      expect { ledger.record(:users, 42, suite: "live_users") }.to unsafe(/symlinks/)
      expect(File.read(target)).to eq('{"version":1,"entries":[]}')
      expect(File.symlink?(path)).to be(true)
    end

    it "rejects a ledger symlinked to a repository file" do
      Dir.mkdir(state, 0o700)
      target = File.join(root, "CHANGELOG.md")
      before = File.read(target)
      File.symlink(target, path)
      expect { ledger.pending }.to unsafe(/symlinks/)
      expect(File.read(target)).to eq(before)
    end

    it "rejects a symlinked lock file" do
      Dir.mkdir(state, 0o700)
      target = File.join(@directory, "lock-target")
      File.write(target, "", perm: 0o600)
      File.symlink(target, "#{path}.lock")
      expect { ledger.pending }.to unsafe(/symlinks/)
    end

    it "rejects a ledger directory reached through a user-owned symlink" do
      real = File.join(@directory, "real-state")
      Dir.mkdir(real, 0o700)
      File.symlink(real, state)
      expect { ledger.record(:users, 42, suite: "live_users") }.to unsafe(/through a symlink/)
      expect(Dir.children(real)).to be_empty
    end

    it "rejects a parent directory that other users can write" do
      shared = File.join(@directory, "shared")
      Dir.mkdir(shared)
      File.chmod(0o777, shared)
      nested = described_class.new(File.join(shared, "state", "ledger.json"), host: "sandbox.example.invalid")
      expect { nested.record(:users, 42, suite: "live_users") }.to unsafe(/untrusted parent/)
      expect(Dir.children(shared)).to be_empty
    end

    it "refuses repository paths, including traversal and symlinks that resolve into the repository" do
      expect(described_class.path({}, repository_root: root)).to eq(described_class::DEFAULT_PATH)
      expect(described_class.path({ "FIVE_PM_LIVE_LEDGER" => path }, repository_root: root)).to eq(path)
      traversal = File.join(root, "..", File.basename(root), "spec", "ledger.json")
      [File.join(root, "tmp", "ledger.json"), root, traversal].each do |inside|
        expect { described_class.path({ "FIVE_PM_LIVE_LEDGER" => inside }, repository_root: root) }
          .to unsafe(/outside the repository/)
      end
      fake_root = File.join(@directory, "repository")
      Dir.mkdir(fake_root, 0o700)
      inside_real = File.join(fake_root, "state")
      Dir.mkdir(inside_real, 0o700)
      File.symlink(inside_real, state)
      redirected = described_class.new(path, host: "sandbox.example.invalid", repository_root: fake_root)
      expect { redirected.pending }.to unsafe(/outside the repository|through a symlink/)
    end

    it "creates nothing when a trusted symlink would redirect a missing directory into the repository" do
      # Treat the current user like root so this symlink counts as a trusted system link.
      stub_const("LiveCleanupLedger::ROOT_UID", Process.uid)
      fake_root = File.join(@directory, "repository")
      Dir.mkdir(fake_root, 0o700)
      link = File.join(@directory, "system-link")
      File.symlink(fake_root, link)
      redirected = described_class.new(File.join(link, "new-state", "ledger.json"),
                                       host: "sandbox.example.invalid", repository_root: fake_root)
      expect { redirected.record(:users, 42, suite: "live_users") }.to unsafe(/outside the repository/)
      expect(Dir.children(fake_root)).to be_empty
    end

    it "never reuses a leftover temporary file" do
      Dir.mkdir(state, 0o700)
      leftover = File.join(state, ".ledger.json.stale.tmp")
      File.write(leftover, "stale", perm: 0o644)
      ledger.record(:users, 42, suite: "live_users")
      expect(File.stat(path).mode & 0o777).to eq(0o600)
      expect(File.read(leftover)).to eq("stale")
    end
  end
end
