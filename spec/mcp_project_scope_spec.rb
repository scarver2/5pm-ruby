require "spec_helper"
require "five_pm/mcp"

RSpec.describe "trusted MCP project scope" do
  let(:client) { double("client") }
  let(:resource) { double("resource") }

  def rpc(adapter, name, arguments = {})
    message = { jsonrpc: "2.0", id: 1, method: "tools/call",
                params: { name: name, arguments: arguments } }
    JSON.parse(adapter.server.handle_json(JSON.generate(message)))
  end

  def adapter(ids = [12])
    FivePM::MCPAdapter::Server.new(client: client, project_ids: ids)
  end

  it "rejects invalid trusted scopes and scoped mutations at construction" do
    [[], [0], [-1], ["12"], [nil], false, "12", Array.new(1001, 12)].each do |ids|
      expect { adapter(ids) }.to raise_error(ArgumentError)
    end
    expect do
      FivePM::MCPAdapter::Server.new(client: client, project_ids: [12], allow_mutations: true,
                                     approver: ->(_proposal) { true })
    end.to raise_error(ArgumentError, /read-only/)
  end

  it "hides global tools, project listings and mutations from scoped discovery and dispatch" do
    scoped = adapter
    reply = JSON.parse(scoped.server.handle_json(JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/list")))
    expect(reply.dig("result", "tools").map { |tool| tool.fetch("name") }).to match_array(
      %w[five_pm_get_projects five_pm_get_tasks five_pm_list_tasks five_pm_get_activity five_pm_list_activity]
    )
    expect(client).not_to receive(:users)
    expect(rpc(scoped, "five_pm_list_users")).to have_key("error")
  end

  it "copies trusted IDs so the host cannot accidentally expand an existing instance" do
    ids = [12]
    scoped = adapter(ids)
    ids << 99
    expect(client).not_to receive(:tasks)
    expect(rpc(scoped, "five_pm_list_tasks", filter: { projectId: 99 }).dig("result", "isError")).to be(true)
  end

  it "injects a single trusted project while preserving pagination and caller filters" do
    expect(client).to receive(:tasks).and_return(resource)
    expect(resource).to receive(:list).with(filter: { "projectId" => 12, "active" => true }, offset: 20, count: 1)
                                      .and_return("list" => { "items" => [{ "id" => 7, "projectId" => "12" }] })
    reply = rpc(adapter, "five_pm_list_tasks", offset: 20, limit: 1, filter: { active: true })
    expect(reply.dig("result", "isError")).to be(false)
    expect(reply.dig("result", "structuredContent", "data", "next_offset")).to eq(21)
  end

  it "rejects conflicting filters and requires an explicit project for multiple IDs before I/O" do
    expect(client).not_to receive(:tasks)
    [{}, { filter: { projectId: 99 } }].each do |args|
      expect(rpc(adapter([12, 13]), "five_pm_list_tasks", args).dig("result", "isError")).to be(true)
    end
  end

  it "accepts an explicit member of a multi-project scope" do
    expect(client).to receive(:activity).and_return(resource)
    expect(resource).to receive(:list).with(filter: { "projectId" => 13 }, offset: 0, count: 20)
                                      .and_return("data" => { "items" => [{ "id" => 7, "projectId" => 13 }] })
    expect(rpc(adapter([12, 13]), "five_pm_list_activity", filter: { projectId: 13 })
      .dig("result", "isError")).to be(false)
  end

  it "rejects a whole page if the server ignores its project filter, including later pages" do
    allow(client).to receive(:tasks).and_return(resource)
    [0, 100].each do |offset|
      expect(resource).to receive(:list).with(filter: { "projectId" => 12 }, offset: offset, count: 20)
                                        .and_return("list" => { "items" => [{ "id" => 7, "projectId" => 13,
                                                                              "name" => "private-other" }] })
      reply = rpc(adapter([12, 13]), "five_pm_list_tasks", offset: offset, filter: { projectId: 12 })
      expect(reply.dig("result", "isError")).to be(true)
      expect(reply.to_json).not_to include("private-other")
    end
  end

  it "requires project identity on direct task and activity reads" do
    %w[tasks activity].each do |service|
      allow(client).to receive(service).and_return(resource)
      [{ "id" => 7 }, { "id" => 7, "projectId" => 99 },
       { "id" => 8, "projectId" => 12 }].each do |row|
        expect(resource).to receive(:get).with(7).and_return("data" => row.merge("name" => "private-other"))
        reply = rpc(adapter, "five_pm_get_#{service}", id: 7)
        expect(reply.dig("result", "isError")).to be(true)
        expect(reply.to_json).not_to include("private-other")
      end
    end
  end

  it "validates typed response envelopes and nested project references before returning data" do
    allow(client).to receive(:tasks).and_return(resource)
    row = { "id" => "7", "projectId" => "12", "future" => [{ "projectId" => 99, "name" => "private-other" }] }
    typed = FivePM::Response.new({ "data" => row }, contract: FivePM::OPERATIONS.dig("tasks", "getById"))
    expect(resource).to receive(:get).with(7).and_return(typed)
    reply = rpc(adapter, "five_pm_get_tasks", id: 7)
    expect(reply.dig("result", "isError")).to be(true)
    expect(reply.to_json).not_to include("private-other")
    expect(resource).to receive(:get).with(7).and_return("data" => { "id" => "7", "projectId" => "12" })
    expect(rpc(adapter, "five_pm_get_tasks", id: 7).dig("result", "isError")).to be(false)
  end

  it "rejects out-of-scope project IDs before I/O and verifies in-scope response identity" do
    scoped = adapter
    expect(client).not_to receive(:projects)
    expect(rpc(scoped, "five_pm_get_projects", id: 99).dig("result", "isError")).to be(true)
  end

  it "allows only the requested configured project record" do
    allow(client).to receive(:projects).and_return(resource)
    expect(resource).to receive(:get).with(12).and_return("project" => { "id" => "12" })
    expect(rpc(adapter, "five_pm_get_projects", id: 12).dig("result", "isError")).to be(false)
    expect(resource).to receive(:get).with(12).and_return("project" => { "id" => "99" })
    expect(rpc(adapter, "five_pm_get_projects", id: 12).dig("result", "isError")).to be(true)
  end
end
