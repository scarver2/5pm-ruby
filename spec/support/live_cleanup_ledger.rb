# spec/support/live_cleanup_ledger.rb
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "time"

# A protected, local-only record of live test records awaiting confirmed deletion.
# It survives crashes and failed runs so the next run can finish cleanup before it
# creates anything new. It holds record IDs, so it must stay outside the repository
# and is never copied into reports. The tenant host is stored only as a SHA-256 digest.
class LiveCleanupLedger
  DEFAULT_PATH = File.join(Dir.home, ".local", "state", "five-pm-ruby", "live-cleanup-ledger.json")
  REPOSITORY_ROOT = File.expand_path("../..", __dir__)

  class UnsafeLedgerError < StandardError; end

  def self.path(environment = ENV, repository_root: REPOSITORY_ROOT)
    path = File.expand_path(environment.fetch("FIVE_PM_LIVE_LEDGER", DEFAULT_PATH))
    root = File.expand_path(repository_root)
    if path == root || path.start_with?("#{root}#{File::SEPARATOR}")
      raise UnsafeLedgerError, "cleanup ledger must be outside the repository"
    end

    path
  end

  attr_reader :path

  def initialize(path, host:)
    @path = path
    @tenant = Digest::SHA256.hexdigest(host.to_s.downcase)
  end

  # Entries for this tenant, oldest first.
  def pending
    synchronize(write: false) { |entries| entries.select { |entry| entry["tenant"] == @tenant } }
  end

  def record(service, id, suite:)
    entry = { "tenant" => @tenant, "service" => service.to_s, "id" => id.to_s, "suite" => suite.to_s,
              "recorded_at" => Time.now.utc.iso8601 }
    synchronize do |entries|
      entries << entry unless entries.any? { |existing| same?(existing, service, id) }
      entries
    end
    nil
  end

  def resolve(service, id)
    synchronize { |entries| entries.reject { |entry| same?(entry, service, id) } }
    nil
  end

  # Confirms deletion of every pending entry for this tenant, newest first so child
  # records go before their parents. Entries whose deletion cannot be confirmed stay
  # in the ledger; the method then raises so the caller creates nothing new.
  def drain!
    failures = 0
    pending.reverse_each do |entry|
      yield entry.fetch("service"), entry.fetch("id")
      resolve(entry.fetch("service"), entry.fetch("id"))
    rescue StandardError
      failures += 1
    end
    raise FivePM::ProtocolError, "earlier live records still await cleanup" if failures.positive?

    nil
  end

  private

  def same?(entry, service, id)
    entry["tenant"] == @tenant && entry["service"] == service.to_s && entry["id"] == id.to_s
  end

  # Reads under an exclusive lock. With write: true the block's returned entries are
  # written back atomically with owner-only permissions.
  def synchronize(write: true)
    directory = File.dirname(@path)
    FileUtils.mkdir_p(directory, mode: 0o700)
    File.open("#{@path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)
      entries = read_entries
      result = yield entries.map(&:dup)
      write_entries(result) if write && result != entries
      result
    end
  end

  def read_entries
    return [] unless File.exist?(@path)

    unless File.stat(@path).mode.nobits?(0o077)
      raise UnsafeLedgerError, "cleanup ledger must not be readable by other users"
    end

    document = JSON.parse(File.read(@path))
    entries = document.is_a?(Hash) ? document["entries"] : nil
    raise UnsafeLedgerError, "cleanup ledger is malformed" unless entries.is_a?(Array)

    entries
  end

  def write_entries(entries)
    temporary = "#{@path}.#{Process.pid}.tmp"
    File.open(temporary, File::WRONLY | File::CREAT | File::TRUNC, 0o600) do |file|
      file.write(JSON.pretty_generate("version" => 1, "entries" => entries))
      file.flush
      file.fsync
    end
    File.rename(temporary, @path)
  ensure
    FileUtils.rm_f(temporary) if temporary && File.exist?(temporary)
  end
end
