# bin/support/cached_validation.rb
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "optparse"
require "tempfile"
require "time"

# Stores only sanitized read/contract evidence; never stores API response bodies.
class FivePMCachedValidation
  def initialize(root: File.expand_path("../..", __dir__), environment: ENV)
    @root = root
    @environment = environment
  end

  def run(arguments)
    options = { service: "5pm-ruby.validation", refresh: false, setup: false, disposable: false }
    parser = OptionParser.new do |cli|
      cli.banner = "Usage: bin/validate [--setup | --refresh] [--disposable] [--service NAME] [--cache FILE]"
      cli.on("--setup", "Prompt to store host, login and password in macOS Keychain") { options[:setup] = true }
      cli.on("--refresh", "Explicitly replace the cached read/contract validation") { options[:refresh] = true }
      cli.on("--disposable", "Confirm this is a designated disposable tenant") { options[:disposable] = true }
      cli.on("--service NAME", "Keychain service prefix (default: 5pm-ruby.validation)") { |v| options[:service] = v }
      cli.on("--cache FILE", "Override the local sanitized cache path") { |v| options[:cache] = v }
      cli.on("-h", "--help") { options[:help] = true }
    end
    parser.parse!(arguments)
    return puts(parser) if options[:help]

    raise ArgumentError, parser.to_s unless arguments.empty? && !(options[:setup] && options[:refresh])
    raise ArgumentError, "service must not be empty" if options[:service].empty?

    return setup(options[:service]) if options[:setup]

    cache = options[:cache] || File.join(@environment.fetch("HOME"), "Library/Caches/5pm-ruby",
                                         "#{Digest::SHA256.hexdigest(options[:service])}.json")
    if File.exist?(cache) && !options[:refresh]
      report = JSON.parse(File.read(cache))
      unless report["format"] == 1 && report["result"] == "passed"
        raise ArgumentError, "invalid cached evidence; review the file or explicitly use --refresh"
      end

      puts JSON.pretty_generate(report.merge("cached" => true,
                                             "source_matches" => report["source_sha256"] == fingerprint))
      return
    end
    raise ArgumentError, "live validation requires --disposable; no request was sent" unless options[:disposable]

    refresh(options[:service], cache)
  end

  private

  def setup(service)
    %w[host login password].each do |field|
      puts "Enter #{field} for the disposable 5PM tenant at the Keychain prompt:"
      # A final -w makes security prompt; secrets never become process arguments.
      success = system("/usr/bin/security", "add-generic-password", "-U", "-a", "5pm-ruby",
                       "-s", "#{service}.#{field}", "-w")
      raise ArgumentError, "Keychain setup failed; retry --setup" unless success
    end
    puts "Keychain configured. Cached evidence was not changed."
  end

  def credential(service, field)
    output, _, status = Open3.capture3("/usr/bin/security", "find-generic-password", "-a", "5pm-ruby",
                                       "-s", "#{service}.#{field}", "-w")
    raise ArgumentError, "Keychain item unavailable; run --setup" unless status.success?

    output.delete_suffix("\n")
  end

  def fingerprint
    paths = Dir.glob("{lib,mcp/lib,bin,spec/support}/**/*", base: @root).select do |path|
      File.file?(File.join(@root, path))
    end.sort
    digest = Digest::SHA256.new
    paths.each do |path|
      bytes = File.binread(File.join(@root, path))
      digest.update("#{path}\0#{bytes.bytesize}\0").update(bytes)
    end
    digest.hexdigest
  end

  def refresh(service, cache)
    host = credential(service, "host")
    environment = { "FIVE_PM_HOST" => host, "FIVE_PM_LOGIN" => credential(service, "login"),
                    "FIVE_PM_PASSWORD" => credential(service, "password"), "FIVE_PM_SANDBOX" => "1",
                    "FIVE_PM_SANDBOX_HOST" => host, "FIVE_PM_ALLOW_MUTATIONS" => nil }
    before = fingerprint
    output, _, status = Open3.capture3(environment, RbConfig.ruby, File.join(@root, "bin/live-check"), chdir: @root)
    unless status.success?
      raise ArgumentError,
            "live validation failed; existing cache preserved; no raw response was saved"
    end

    result = JSON.parse(output)
    unless result["result"] == "passed" && result["mutations_enabled"] == false &&
           result["worktree_dirty"] == false && before == fingerprint
      raise ArgumentError, "validation did not pass on a stable, clean source tree; cache preserved"
    end

    # Whitelist local metadata. Raw reports, credentials, IDs and tokens are discarded.
    report = { format: 1, result: "passed", scope: "contract_and_reads", release_evidence: false,
               mutations_verified: false, validated_at: Time.now.utc.iso8601,
               evidence_commit: result.fetch("evidence_commit"), source_sha256: before }
    FileUtils.mkdir_p(File.dirname(cache), mode: 0o700)
    Tempfile.create(["validation-", ".json"], File.dirname(cache)) do |file|
      file.chmod(0o600)
      file.write("#{JSON.pretty_generate(report)}\n")
      file.close
      File.rename(file.path, cache)
    end
    puts JSON.pretty_generate(report.merge(cached: false))
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    FivePMCachedValidation.new.run(ARGV)
  rescue ArgumentError, JSON::ParserError, KeyError, SystemCallError => e
    warn "Validation stopped: #{e.is_a?(ArgumentError) ? e.message : e.class.name}"
    exit 1
  end
end
