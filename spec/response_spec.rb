require "spec_helper"
require "rexml/document"

RSpec.describe FivePM::Response do
  def fixture(name)
    JSON.parse(File.read(File.join(__dir__, "fixtures/synthetic/#{name}.json")))
  end

  def mapped(name, service:, operation:)
    described_class.new(fixture(name), contract: FivePM::OPERATIONS.fetch(service).fetch(operation))
  end

  it "maps nested project lists, members, counters and booleans without losing any JSON" do
    source = fixture("projects")
    response = described_class.new(source, contract: FivePM::OPERATIONS.dig("projects", "getList"))
    expect(response.list).to be_a(FivePM::Models::ProjectList)
    expect(response.list.count).to eq(1)
    expect(response.list.total).to eq(12)
    expect(response.list.to_h).to eq(source.fetch("list"))
    project = response.list.first
    expect(project).to be_a(FivePM::Models::Project)
    expect(project.id).to eq(123)
    expect(project.hidden).to be(false)
    expect(project.team.first.first_name).to eq("Test")
    # The XSD declares this field string, despite its suggestive name.
    expect(project.team.first.can_view_profiles).to eq("1")
    expect(project["futureProject"]).to eq("nested" => [false, nil, "unchanged"])
    expect(response["futureEnvelope"]).to eq("trace" => "synthetic-trace")
    expect(response.to_h).to eq(source)
    expect(response.to_h).not_to equal(source)
    expect(source["list"]["items"].first["id"]).to eq("123")
  end

  it "preserves explicit time offsets and timezone-free dates exactly" do
    project = mapped("projects", service: "projects", operation: "getList").list.first
    expect(project.start_date).to eq("2026-10-28T09:30:00-05:00")
    expect(project.end_date).to eq("2026-11-01T17:00:00")
  end

  it "maps tasks and float fields without rounding or changing the raw representation" do
    task = mapped("tasks", service: "tasks", operation: "getById").task
    expect(task).to be_a(FivePM::Models::Task)
    expect([task.id, task.project_id, task.parent_id]).to eq([456, 123, 99])
    expect([task.progress, task.hours_done, task.estimated_time]).to eq([34.5, 1.25, 2.0])
    expect(task.can_edit).to be(false)
    expect(task.team.to_a).to eq([])
    expect(task.raw["hoursDone"]).to eq("1.25")
  end

  it "maps activities, attached file metadata and nested image information without fetching URLs" do
    activity = mapped("activity", service: "activity", operation: "getById").activity
    expect(activity).to be_a(FivePM::Models::Activity)
    expect(activity.progress).to eq(34)
    file = activity.files.first
    expect(file).to be_a(FivePM::Models::File)
    expect(file.size).to eq(128)
    expect(file.can_thumb).to be(true)
    expect(file.image_info).to be_a(FivePM::Models::ImageInfo)
    expect(file.image_info.width).to eq(640)
    expect(file.image_info["futureImage"]).to eq("retained")
  end

  it "maps groups and keeps all parts of multi-part user responses" do
    group = mapped("project_groups", service: "projectsgroups", operation: "getById").group
    expect(group).to be_a(FivePM::Models::ProjectsGroup)
    expect(group.id).to eq(4)
    users = mapped("users", service: "users", operation: "getAll")
    expect(users.session_id).to eq("synthetic-response-token")
    expect(users.list.first).to be_a(FivePM::Models::User)
    expect(users.list.first.security_level).to eq("100")
    expect(users.list.first.timezone).to eq(-5)
    expect(users.to_h).to eq(fixture("users"))
    expect(users).to respond_to(:session_id, :list)
    expect(users).not_to respond_to(:future_envelope)
    expect { users.future_envelope }.to raise_error(NoMethodError)
    expect { users.list(1) }.to raise_error(NoMethodError)
  end

  it "maps authentication and mutation scalar results without confusing false and absent values" do
    response = described_class.new({ "auth" => { "sessionId" => "synthetic-token" } },
                                   contract: FivePM::OPERATIONS.dig("authentication", "signIn"))
    expect(response.auth).to be_a(FivePM::Models::AuthToken)
    expect(response.auth.session_id).to eq("synthetic-token")
    deletion = described_class.new({ "status" => "false" }, contract: FivePM::OPERATIONS.dig("tasks", "remove"))
    expect(deletion.status).to be(false)
    expect(deletion.key?(:status)).to be(true)
    expect(deletion.key?(:missing)).to be(false)
    expect(deletion[:missing]).to be_nil
    missing = FivePM::Models::Task.new({})
    expect(missing.id).to be_nil
    expect(missing.to_h).to eq({})
    expect(FivePM::Models::UserList.new({}).to_a).to eq([])
    expect(FivePM::Models::Task.new({ "id" => nil }).id).to be_nil
  end

  it "keeps immutable snapshots independent of caller mutations" do
    source = fixture("projects")
    response = described_class.new(source, contract: FivePM::OPERATIONS.dig("projects", "getList"))
    source["list"]["items"].first["name"].replace("changed")
    expect(response.list.first.name).to eq("Synthetic project")
    expect { response.raw["list"]["items"] << {} }.to raise_error(FrozenError)
    expect { response.list.items << {} }.to raise_error(FrozenError)
    expect { response.list.first.name.replace("changed") }.to raise_error(FrozenError)
    expect(response).to be_frozen
  end

  it "never includes sensitive or unknown values in inspection" do
    users = mapped("users", service: "users", operation: "getAll")
    expect(users.inspect).to eq("#<FivePM::Response>")
    expect(users.list.inspect).to eq("#<FivePM::Models::UserList>")
    expect(users.list.first.inspect).to eq("#<FivePM::Models::User>")
    expect(FivePM::Models::AuthToken.new({ "sessionId" => "secret" }).inspect).not_to include("secret")
  end

  it "rejects malformed known types and shapes without leaking values" do
    [{ "id" => "synthetic-secret" }, { "id" => 1.5 }, { "hidden" => "synthetic-secret" },
     { "name" => {} }, { "startDate" => 5 }, { "team" => [] }, { "hoursDone" => "NaN" },
     { "hoursDone" => "1e9999" }, { "hoursDone" => [] }, { "hidden" => 1.0 }].each do |payload|
      expect { FivePM::Models::Task.new(payload) }.to raise_error(FivePM::ProtocolError) do |error|
        expect(error.message).not_to include("synthetic-secret")
        expect(error.cause).to be_nil
      end
    end
    expect { FivePM::Models::TaskList.new({ "items" => {} }) }.to raise_error(FivePM::ProtocolError)
    expect { FivePM::Models::TaskList.new({ "items" => [nil] }) }.to raise_error(FivePM::ProtocolError)
    expect { described_class.new([], contract: FivePM::OPERATIONS.dig("tasks", "getList")) }
      .to raise_error(FivePM::ProtocolError)
  end

  it "accepts XSD boolean lexical values and numeric float representations" do
    [true, 1, "1", "true"].each { |value| expect(FivePM::Models::Task.new({ "hidden" => value }).hidden).to be(true) }
    [false, 0, "0", "false"].each { |value| expect(FivePM::Models::Task.new({ "hidden" => value }).hidden).to be(false) }
    expect(FivePM::Models::Task.new({ "hoursDone" => "1.25e2" }).hours_done).to eq(125.0)
    expect(FivePM::Models::Task.new({ "id" => 0 }).id).to eq(0)
  end

  it "matches every response model field and repeated-item type to the upstream XSD" do
    document = REXML::Document.new(File.read(File.join(__dir__, "fixtures/wsdl/schema.xsd")))
    types = {}
    ns = { "x" => "http://www.w3.org/2001/XMLSchema" }
    REXML::XPath.each(document, "//x:complexType", ns) do |node|
      name = node.attributes["name"]
      next if name.end_with?("Filter")

      types[name] = REXML::XPath.match(node, "x:sequence/x:element", ns).to_h do |field|
        [field.attributes["name"], { "type" => field.attributes["type"].split(":").last,
                                     "repeated" => field.attributes["maxOccurs"] == "unbounded" }]
      end
    end
    expect(FivePM::Models::TYPES).to eq(types)
    FivePM::OPERATIONS.each_value do |operations|
      operations.each_value do |operation|
        operation.fetch("response").each_value do |type|
          next if type.start_with?("xsd:")

          expect(FivePM::Models.const_get(type.split(":").last, false)).to be < FivePM::Models::Record
        end
      end
    end
  end
end
