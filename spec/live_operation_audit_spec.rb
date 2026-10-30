require "spec_helper"
require "tempfile"
require_relative "support/live_operation_audit"

RSpec.describe LiveOperationAudit do
  let(:transport) do
    Class.new do
      prepend LiveOperationAudit

      def post(_service, _operation, parameters)
        raise FivePM::APIError, 441 if parameters["fail"]

        { "data" => { "password" => "private-payload" } }
      end

      def download_file(_parameters)
        FivePM::Download.new(bytes: "private-binary", content_type: nil)
      end
    end.new
  end

  it "records only successful operation names, never arguments, payloads or binary contents" do
    Tempfile.create("five-pm-audit-test") do |file|
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("FIVE_PM_LIVE_AUDIT").and_return(file.path)
      transport.post("tasks", "getById", { "id" => 7, "sessionId" => "private-token" })
      transport.download_file("id" => 7)
      expect { transport.post("tasks", "getById", { "fail" => true }) }.to raise_error(FivePM::APIError)
      events = File.readlines(file.path).map { |line| JSON.parse(line) }
      expect(events).to eq([{ "service" => "tasks", "operation" => "getById" },
                            { "service" => "activity", "operation" => "downloadFile" }])
      expect(File.read(file.path)).not_to include("private")
    end
  end

  it "preserves the API outcome when the audit sink fails and emits a fixed diagnostic" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("FIVE_PM_LIVE_AUDIT").and_raise(KeyError, "private-path")
    expect do
      expect(transport.post("tasks", "getById", {})).to eq("data" => { "password" => "private-payload" })
    end.to output("{\"result\":\"failed\",\"stage\":\"operation_audit\"}\n").to_stderr
  end
end
