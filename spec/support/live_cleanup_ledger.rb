# spec/support/live_cleanup_ledger.rb
# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"
require "time"

# A protected, local-only record of live test records awaiting confirmed deletion.
# It survives crashes and failed runs so the next run can finish cleanup before it
# creates anything new. It holds record IDs, so it must stay outside the repository
# and is never copied into reports. The tenant host is stored only as a SHA-256 digest.
#
# Storage fails closed: the ledger directory must be a real (non-symlink) directory
# owned by the current user with no group/other access, every ancestor must be a
# trusted directory, and the ledger and lock must be regular owner-only files opened
# without following symlinks. Invalid state raises before anything is written.
class LiveCleanupLedger
  DEFAULT_PATH = File.join(Dir.home, ".local", "state", "five-pm-ruby", "live-cleanup-ledger.json")
  REPOSITORY_ROOT = File.expand_path("../..", __dir__)
  NOFOLLOW = File.const_defined?(:NOFOLLOW) ? File::NOFOLLOW : nil
  ROOT_UID = 0
  VERSION = 1
  # Each suite may only record (and later delete) these services.
  SUITE_SERVICES = { "live_attachments" => %w[projects tasks activity], "live_users" => %w[users] }.freeze
  ENTRY_KEYS = %w[id recorded_at service suite tenant].freeze
  TENANT_DIGEST = /\A\h{64}\z/
  IDENTIFIER = /\A[1-9][0-9]{0,18}\z/

  class UnsafeLedgerError < StandardError; end

  def self.path(environment = ENV, repository_root: REPOSITORY_ROOT)
    path = File.expand_path(environment.fetch("FIVE_PM_LIVE_LEDGER", DEFAULT_PATH))
    reject_inside!(path, File.expand_path(repository_root))
    path
  end

  def self.reject_inside!(path, root)
    return unless path == root || path.start_with?("#{root}#{File::SEPARATOR}")

    raise UnsafeLedgerError, "cleanup ledger must be outside the repository"
  end

  attr_reader :path

  def initialize(path, host:, repository_root: REPOSITORY_ROOT)
    @path = File.expand_path(path)
    @repository_root = repository_root
    @tenant = Digest::SHA256.hexdigest(host.to_s.downcase)
  end

  # Entries for this tenant (optionally one suite), oldest first.
  def pending(suite: nil)
    raise ArgumentError, "unknown live suite" unless suite.nil? || SUITE_SERVICES.key?(suite.to_s)

    synchronize(write: false) do |entries|
      entries.select { |entry| entry["tenant"] == @tenant && (suite.nil? || entry["suite"] == suite.to_s) }
    end
  end

  def record(service, id, suite:)
    entry = { "tenant" => @tenant, "service" => service.to_s, "id" => id.to_s, "suite" => suite.to_s,
              "recorded_at" => Time.now.utc.iso8601 }
    validate_entry!(entry)
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

  # Confirms deletion of this suite's pending entries for this tenant, newest first so
  # child records go before their parents. Other suites' entries are left alone, so a
  # User only an Administrator can delete never blocks attachment checks. Entries
  # whose deletion cannot be confirmed stay; the method then raises so the caller
  # creates nothing new. Only failures from the deletion callback are counted and
  # skipped; ledger safety errors stop the drain immediately.
  def drain!(suite:)
    failures = 0
    pending(suite: suite).reverse_each do |entry|
      begin
        yield entry.fetch("service"), entry.fetch("id")
      rescue UnsafeLedgerError
        raise
      rescue StandardError
        failures += 1
        next
      end
      resolve(entry.fetch("service"), entry.fetch("id"))
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
    raise UnsafeLedgerError, "cleanup ledger needs O_NOFOLLOW support" unless NOFOLLOW

    directory = secure_directory!
    path = File.join(directory, File.basename(@path))
    File.open("#{path}.lock", File::RDWR | File::CREAT | NOFOLLOW, 0o600) do |lock|
      owner_only_file!(lock, "cleanup ledger lock")
      lock.flock(File::LOCK_EX)
      entries = read_entries(path)
      result = yield entries.map(&:dup)
      write_entries(directory, path, result) if write && result != entries
      result
    end
  rescue Errno::ELOOP
    raise UnsafeLedgerError, "cleanup ledger files must not be symlinks"
  end

  # Returns the canonical ledger directory after checking every component.
  def secure_directory!
    directory = File.dirname(@path)
    self.class.reject_inside!(directory, File.expand_path(@repository_root))
    create_directory!(directory)
    real = File.realpath(directory)
    self.class.reject_inside!(real, File.realpath(@repository_root))
    trusted_ancestors!(real)
    stat = File.lstat(real)
    unless stat.directory? && stat.uid == Process.uid && stat.mode.nobits?(0o077)
      raise UnsafeLedgerError, "cleanup ledger directory must be owned by you with mode 0700"
    end

    real
  end

  # Creates missing components owner-only, refusing symlinks that are not owned by
  # root (system links such as /var or /tmp on macOS are acceptable). Before each
  # directory is created, its canonical location is checked against the repository
  # and its parents are checked for trust, so an unsafe path never creates anything.
  def create_directory!(directory)
    repository = File.realpath(@repository_root)
    current = File::SEPARATOR
    directory.split(File::SEPARATOR).reject(&:empty?).each do |component|
      current = File.join(current, component)
      begin
        stat = File.lstat(current)
      rescue Errno::ENOENT
        target = File.join(File.realpath(File.dirname(current)), component)
        self.class.reject_inside!(target, repository)
        trusted_ancestors!(target)
        Dir.mkdir(current, 0o700)
        next
      end
      next unless stat.symlink?
      next if stat.uid == ROOT_UID

      raise UnsafeLedgerError, "cleanup ledger path must not pass through a symlink"
    end
  end

  # Each ancestor of the canonical directory must be owned by root or you, and not
  # writable by others unless sticky (as /tmp is).
  def trusted_ancestors!(real)
    ancestor = File.dirname(real)
    loop do
      stat = File.lstat(ancestor)
      writable_by_others = stat.mode.anybits?(0o022) && !stat.sticky?
      if ![ROOT_UID, Process.uid].include?(stat.uid) || writable_by_others
        raise UnsafeLedgerError, "cleanup ledger directory has an untrusted parent"
      end
      break if ancestor == File::SEPARATOR

      ancestor = File.dirname(ancestor)
    end
  end

  def owner_only_file!(file, label)
    stat = file.stat
    return if stat.file? && stat.uid == Process.uid && stat.mode.nobits?(0o077)

    raise UnsafeLedgerError, "#{label} must be a regular file readable only by you"
  end

  # A Hash that refuses a repeated key, so JSON.parse cannot silently keep only the
  # last of two "entries" arrays or two values for one entry field.
  class UniqueKeyHash < Hash
    def []=(key, value)
      raise UnsafeLedgerError, "cleanup ledger has duplicate keys" if key?(key)

      super
    end
  end

  def read_entries(path)
    document = File.open(path, File::RDONLY | NOFOLLOW) do |file|
      owner_only_file!(file, "cleanup ledger")
      JSON.parse(file.read, object_class: UniqueKeyHash)
    end
    validate_document!(document)
  rescue Errno::ENOENT
    []
  rescue JSON::ParserError
    raise UnsafeLedgerError, "cleanup ledger is malformed"
  end

  # Validates the whole document before any entry is filtered, deleted or added, so a
  # malformed or ambiguous entry can never be silently skipped or routed to the wrong
  # suite's deletion code. Invalid ledgers are refused and left unchanged.
  def validate_document!(document)
    unless document.is_a?(Hash) && document.keys.sort == %w[entries version] && document["version"] == VERSION
      raise UnsafeLedgerError, "cleanup ledger is malformed or an unsupported version"
    end

    entries = document["entries"]
    raise UnsafeLedgerError, "cleanup ledger is malformed" unless entries.is_a?(Array)

    entries.each { |entry| validate_entry!(entry) }
    keys = entries.map { |entry| entry.values_at("tenant", "service", "id") }
    raise UnsafeLedgerError, "cleanup ledger has duplicate entries" unless keys.uniq.length == keys.length

    entries
  end

  def validate_entry!(entry)
    valid = entry.is_a?(Hash) && entry.keys.sort == ENTRY_KEYS &&
            entry.values.all?(String) && TENANT_DIGEST.match?(entry["tenant"]) &&
            IDENTIFIER.match?(entry["id"]) &&
            SUITE_SERVICES.fetch(entry["suite"], []).include?(entry["service"]) &&
            valid_time?(entry["recorded_at"])
    raise UnsafeLedgerError, "cleanup ledger has an invalid entry" unless valid

    entry
  end

  def valid_time?(value)
    Time.iso8601(value)
    true
  rescue ArgumentError
    false
  end

  def write_entries(directory, path, entries)
    # A fresh, exclusively created name: a leftover or pre-created file is never reused.
    temporary = File.join(directory, ".#{File.basename(path)}.#{SecureRandom.hex(8)}.tmp")
    File.open(temporary, File::WRONLY | File::CREAT | File::EXCL | NOFOLLOW, 0o600) do |file|
      file.chmod(0o600)
      file.write(JSON.pretty_generate("version" => VERSION, "entries" => entries))
      file.flush
      file.fsync
    end
    File.rename(temporary, path)
  ensure
    File.unlink(temporary) if temporary && File.exist?(temporary)
  end
end
