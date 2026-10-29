require "spec_helper"
require "open3"
require "timeout"

RSpec.describe "official MCP SDK over stdio" do
  it "negotiates lifecycle, lists tools, executes synthetic reads and rejects writes without stdout contamination" do
    messages = [
      { jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-11-25", capabilities: {},
                                                               clientInfo: { name: "synthetic-test", version: "1" } } },
      { jsonrpc: "2.0", method: "notifications/initialized" },
      { jsonrpc: "2.0", id: 2, method: "tools/list" },
      { jsonrpc: "2.0", id: 3, method: "tools/call", params: { name: "five_pm_list_tasks", arguments: { limit: 2 } } },
      { jsonrpc: "2.0", id: 4, method: "tools/call", params: { name: "five_pm_get_tasks", arguments: { id: 7 } } },
      { jsonrpc: "2.0", id: 5, method: "tools/call", params: { name: "five_pm_delete_tasks", arguments: { id: 7 } } }
    ]
    script = File.join(__dir__, "support/mcp_stdio_fixture.rb")
    input = "#{messages.map { |message| JSON.generate(message) }.join("\n")}\n"
    stdout, stderr, status = Timeout.timeout(15) do
      Open3.capture3(RbConfig.ruby, "-Imcp/lib", script, stdin_data: input)
    end
    expect(status).to be_success
    responses = stdout.lines.map { |line| JSON.parse(line) }.to_h { |message| [message.fetch("id"), message] }
    expect(responses.keys).to eq([1, 2, 3, 4, 5])
    expect(responses[1].dig("result", "serverInfo", "name")).to eq("five-pm")
    expect(responses[2].dig("result", "tools").length).to eq(10)
    expect(responses[3].dig("result", "structuredContent", "data", "items", 0, "name")).to eq("Synthetic task")
    expect(responses[4].dig("result", "isError")).to be(true)
    expect(responses[5]).to have_key("error")
    expect(stdout + stderr).not_to include("synthetic-password-secret", "synthetic-token-secret", "synthetic-login")
    events = stderr.lines.map { |line| JSON.parse(line) }
    expect(events.map { |event| event.fetch("outcome") }).to eq(%w[success failed rejected])
    expect(events.map { |event| event.fetch("request_id") }.uniq.length).to eq(3)
  end
  it "runs the actual executable with synthetic transport and fails safely on missing credentials" do
    executable = File.join(__dir__, "../mcp/exe/five-pm-mcp")
    preload = File.join(__dir__, "support/mcp_synthetic_transport.rb")
    environment = { "FIVE_PM_HOST" => "example.5pmweb.com", "FIVE_PM_LOGIN" => "synthetic-login",
                    "FIVE_PM_PASSWORD" => "synthetic-password-secret" }
    message = JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/call",
                            params: { name: "five_pm_list_tasks", arguments: { limit: 2 } })
    input = "#{message}\n"
    stdout, stderr, status = Timeout.timeout(15) do
      Open3.capture3(environment, RbConfig.ruby, "-Imcp/lib", "-r", preload, executable, stdin_data: input)
    end
    expect(status).to be_success
    expect(JSON.parse(stdout).dig("result", "structuredContent", "data", "items", 0, "name")).to eq("Synthetic task")
    expect(JSON.parse(stderr).fetch("outcome")).to eq("success")
    expect(stdout + stderr).not_to include("synthetic-password-secret", "synthetic-token-secret")
    stdout, stderr, status = Open3.capture3(environment.merge("FIVE_PM_PASSWORD" => nil), RbConfig.ruby,
                                            "-Imcp/lib", executable, stdin_data: "")
    expect(status).not_to be_success
    expect(stdout).to eq("")
    expect(stderr).to include("check injected environment")
  end
end
