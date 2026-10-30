require "spec_helper"
require "rexml/document"

RSpec.describe FivePM::Response do
  it "maps sanitized live response shapes and rejects observed error envelopes" do
    observed = lambda do |name|
      JSON.parse(File.read(File.join(__dir__, "fixtures/observed/#{name}.json")))
    end
    auth = described_class.new(observed.call("sign_in"), contract: FivePM::OPERATIONS.dig("authentication", "signIn"))
    expect(auth.auth.session_id).to eq("redacted-session-token")
    user = described_class.new(observed.call("authorized_user"),
                               contract: FivePM::OPERATIONS.dig("authentication", "getAuthorizedUser"))
    expect(user.user.can_view_profiles).to be(true)
    projects = described_class.new(observed.call("projects_list"),
                                   contract: FivePM::OPERATIONS.dig("projects", "getList"))
    expect(projects.list.first.id).to eq(123)
    deletion = described_class.new(observed.call("delete_marker"), contract: FivePM::OPERATIONS.dig("tasks", "remove"))
    expect(deletion.status).to eq(1_234_567_890)
    %w[missing_record validation_error].each do |name|
      expect do
        described_class.new(observed.call(name), contract: FivePM::OPERATIONS.dig("tasks", "getById"))
      end.to raise_error(FivePM::APIError)
    end
  end
  it "preserves live integer deletion markers without relaxing record boolean fields" do
    [true, false, 0, 1, 123_456].each do |value|
      response = described_class.new({ "data" => value }, contract: FivePM::OPERATIONS.dig("tasks", "remove"))
      expect(response.status).to eq(value)
      expect(response.to_h).to eq("data" => value)
    end
    expect do
      described_class.new({ "data" => -1 }, contract: FivePM::OPERATIONS.dig("projects", "remove"))
    end.to raise_error(FivePM::SchemaError)
    expect { FivePM::Models::Task.new({ "hidden" => 123_456 }) }.to raise_error(FivePM::SchemaError)
  end
  it "accepts live boolean and WSDL string canViewProfiles values without coercing other user fields" do
    [true, false, "1", "0", "true", "false", nil].each do |value|
      source = { "data" => { "id" => "7", "canViewProfiles" => value } }
      response = described_class.new(source, contract: FivePM::OPERATIONS.dig("authentication", "getAuthorizedUser"))
      expect(response.user.can_view_profiles).to eq(value)
      expect(response.to_h).to eq(source)
      expect(response.user.to_h.fetch("canViewProfiles")).to eq(value)
    end
    [0, 1, {}, []].each do |value|
      expect { FivePM::Models::User.new({ "canViewProfiles" => value }) }.to raise_error(FivePM::SchemaError)
    end
    expect { FivePM::Models::User.new({ "firstName" => false }) }.to raise_error(FivePM::SchemaError)
    list = described_class.new({ "data" => { "items" => [{ "canViewProfiles" => false }] } },
                               contract: FivePM::OPERATIONS.dig("users", "getAll"))
    expect(list.list.first.can_view_profiles).to be(false)
  end

  it "identifies the innermost invalid schema field without retaining its value or cause" do
    source = { "data" => { "items" => [{ "id" => "private-secret" }] } }
    contract = FivePM::OPERATIONS.dig("users", "getAll")
    expect { described_class.new(source, contract: contract) }.to raise_error(FivePM::SchemaError) do |error|
      expect([error.field, error.expected_type, error.actual_type]).to eq(%w[id integer string])
      expect(error.message).not_to include("private-secret")
      expect(error.instance_variables.map { |key| error.instance_variable_get(key) }).not_to include("private-secret")
      expect(error.cause).to be_nil
    end
  end

  it "maps data wrappers for every declared operation while retaining wire serialization" do
    FivePM::OPERATIONS.each_value do |operations|
      operations.each_value do |contract|
        part, type = contract.fetch("response").except("sessionId").first
        type = type.split(":").last
        value = if FivePM::Models::TYPES.key?(type)
                  type.end_with?("List") ? { "items" => [], "count" => 0, "total" => 0 } : { "id" => "7" }
                else
                  false
                end
        value = { "sessionId" => "synthetic-token" } if type == "AuthToken"
        source = { "data" => value, "futureEnvelope" => { "unchanged" => true } }
        response = described_class.new(source, contract: contract)
        if FivePM::Models::TYPES.key?(type)
          expect(response[part]).to be_a(FivePM::Models.const_get(type, false))
          expect(response[part].to_h).to eq(value)
        else
          expect(response[part]).to be(false)
        end
        expect(response.to_h).to eq(source)
        expect(JSON.parse(response.to_json)).to eq(source)
        expect(response["futureEnvelope"]).to eq("unchanged" => true)
      end
    end
  end

  it "rejects ambiguous, error and malformed data wrappers without leaking values" do
    contract = FivePM::OPERATIONS.dig("tasks", "getById")
    [{ "data" => {}, "task" => {} }, { "data" => {}, "success" => false },
     { "data" => {}, "error" => "private-secret" }, { "data" => "private-secret" },
     { "data" => { "id" => "private-secret" } }].each do |payload|
      expect { described_class.new(payload, contract: contract) }.to raise_error(FivePM::ProtocolError) do |error|
        expect(error.message).not_to include("private-secret")
      end
    end
    expect do
      described_class.new({ "data" => { "items" => {} } }, contract: FivePM::OPERATIONS.dig("tasks", "getList"))
    end.to raise_error(FivePM::ProtocolError)
  end

  it "keeps data-wrapper snapshots immutable and user-list session metadata separate" do
    source = { "data" => { "items" => [{ "id" => "7", "firstName" => "Synthetic" }] },
               "sessionId" => "synthetic-token" }
    response = described_class.new(source, contract: FivePM::OPERATIONS.dig("users", "getAll"))
    expect(response.session_id).to eq("synthetic-token")
    expect(response.list.first.id).to eq(7)
    source["data"]["items"].first["firstName"].replace("Changed")
    expect(response.list.first.first_name).to eq("Synthetic")
    expect(response.raw.dig("data", "items", 0, "firstName")).to eq("Synthetic")
    expect { response["data"]["items"].clear }.to raise_error(FrozenError)
    expect { response.list.first.first_name.replace("Changed") }.to raise_error(FrozenError)
  end

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
