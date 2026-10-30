require "spec_helper"
require "tmpdir"
require_relative "support/live_subprocess"

RSpec.describe LiveSubprocess do
  it "drains both pipes while writing input and returns the process status" do
    script = '$stdout.write("x" * 100_000); $stderr.write("y" * 100_000); $stdout.write($stdin.read)'
    output, errors, status = described_class.capture({}, RbConfig.ruby, "-e", script,
                                                     timeout: 10, stdin_data: "input")
    expect(output).to eq("#{'x' * 100_000}input")
    expect(errors).to eq("y" * 100_000)
    expect(status).to be_success
  end

  it "kills a timed-out child rather than hanging in Open3's wait cleanup" do
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    expect do
      described_class.capture({}, RbConfig.ruby, "-e", 'trap("TERM") {}; sleep 30', timeout: 1)
    end.to raise_error(Timeout::Error, "live subprocess timed out")
    expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
  end

  it "bounds inherited pipes after the immediate child exits" do
    Dir.mktmpdir("five-pm-descendant-") do |directory|
      marker = File.join(directory, "forked")
      script = 'fork { sleep 30 }; File.write(ARGV.fetch(0), "ready"); exit!'
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect do
        described_class.capture({}, RbConfig.ruby, "-e", script, marker, timeout: 1)
      end.to raise_error(Timeout::Error)
      expect(File.read(marker)).to eq("ready")
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 5
    end
  end
end
