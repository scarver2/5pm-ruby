# spec/cached_validation_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../bin/support/cached_validation"

RSpec.describe FivePMCachedValidation do
  around do |example|
    Dir.mktmpdir("five-pm-cache-") do |directory|
      @directory = directory
      example.run
    end
  end

  let(:cache) { File.join(@directory, "validation.json") }
  let(:validator) { described_class.new(root: @directory) }
  let(:success) { instance_double(Process::Status, success?: true) }
  let(:failure) { instance_double(Process::Status, success?: false) }

  def mock_live(status: success, result: "passed")
    allow(Open3).to receive(:capture3).with("/usr/bin/security", "find-generic-password", anything,
                                            anything, anything, anything, "-w").and_return(["private-value\n", "",
                                                                                            success])
    payload = { result: result, mutations_enabled: false, worktree_dirty: false,
                evidence_commit: "a" * 40, private_payload: "must-not-be-cached" }
    allow(Open3).to receive(:capture3).with(kind_of(Hash), RbConfig.ruby, anything, chdir: @directory)
                                      .and_return([JSON.generate(payload), "", status])
  end

  it "requires explicit disposable designation before accessing credentials or the network" do
    expect(Open3).not_to receive(:capture3)
    expect { validator.run(["--cache", cache]) }.to raise_error(ArgumentError, /--disposable/)
  end

  it "caches only sanitized metadata and reuses it without credentials or network access" do
    mock_live
    expect { validator.run(["--cache", cache, "--disposable"]) }.to output.to_stdout
    stored = File.read(cache)
    expect(stored).not_to include("private-value", "must-not-be-cached", "private_payload")
    expect(JSON.parse(stored)).to include("release_evidence" => false, "mutations_verified" => false)
    expect(File.stat(cache).mode & 0o777).to eq(0o600)
    expect(Open3).not_to receive(:capture3)
    expect { validator.run(["--cache", cache]) }.to output(/"cached": true/).to_stdout
  end

  it "refuses stale evidence without automatically refreshing" do
    File.write(cache, JSON.generate(format: 1, result: "passed", source_sha256: "old"))
    expect(Open3).not_to receive(:capture3)
    expect { validator.run(["--cache", cache]) }.to raise_error(ArgumentError, /--refresh/)
  end

  it "preserves the previous cache if an explicit refresh fails" do
    File.write(cache, "previous accepted cache")
    mock_live(status: failure, result: "failed")
    expect { validator.run(["--cache", cache, "--refresh", "--disposable"]) }
      .to raise_error(ArgumentError, /existing cache preserved/)
    expect(File.read(cache)).to eq("previous accepted cache")
  end

  it "rejects dirty source instead of caching a passing development run" do
    mock_live
    payload = JSON.generate(result: "passed", mutations_enabled: false, worktree_dirty: true)
    allow(Open3).to receive(:capture3).with(kind_of(Hash), RbConfig.ruby, anything, chdir: @directory)
                                      .and_return([payload, "", success])
    expect { validator.run(["--cache", cache, "--disposable"]) }.to raise_error(ArgumentError, /clean source/)
    expect(File).not_to exist(cache)
  end

  it "uses terminal Keychain prompts rather than secret command arguments" do
    %w[host login password].each do |field|
      expect(validator).to receive(:system).with("/usr/bin/security", "add-generic-password", "-U", "-a",
                                                 "5pm-ruby", "-s", "5pm-ruby.validation.#{field}", "-w")
                                           .and_return(true)
    end
    expect { validator.run(["--setup"]) }.to output(/Keychain configured/).to_stdout
  end
end
