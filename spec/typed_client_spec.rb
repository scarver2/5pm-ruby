require "spec_helper"

RSpec.describe "typed client responses" do
  let(:transport) { double("transport") }
  let(:options) do
    { host: "example.5pmweb.com", login: "synthetic@example.com", password: "synthetic-password",
      response_mode: :typed, transport: transport }
  end
  let(:client) { FivePM::Client.new(**options) }

  before do
    allow(transport).to receive(:post).with("authentication", "signIn", anything)
                                      .and_return("auth" => { "sessionId" => "synthetic-token" })
  end

  it "maps a resource response after signing in and retains its original JSON serialization" do
    payload = JSON.parse(File.read(File.join(__dir__, "fixtures/synthetic/tasks.json")))
    expect(transport).to receive(:post).with("tasks", "getById", { "id" => 456, "sessionId" => "synthetic-token" })
                                       .and_return(payload)
    response = client.tasks.get(456)
    expect(response).to be_a(FivePM::Response)
    expect(response.task.id).to eq(456)
    expect(JSON.parse(JSON.generate(response))).to eq(payload)
    expect(JSON.parse(response.task.to_json)).to eq(payload.fetch("task"))
  end

  it "maps authorized users and sign-out results, then clears the session" do
    expect(transport).to receive(:post).with("authentication", "getAuthorizedUser", anything)
                                       .and_return("user" => { "id" => "7", "firstName" => "Test" })
    expect(client.authentication.call("getAuthorizedUser").user.first_name).to eq("Test")
    expect(transport).to receive(:post).with("authentication", "signOut", anything)
                                       .and_return("signOutState" => "false")
    result = client.sign_out
    expect(result.sign_out_state).to be(false)
    expect(client.sign_out).to be(false)
  end

  it "leaves raw mode responses identical to the transport payload" do
    raw = FivePM::Client.new(**options, response_mode: :raw)
    payload = { "data" => { "items" => [{ "id" => "7" }] }, "futureField" => true }
    expect(transport).to receive(:post).with("users", "getAll", anything).and_return(payload)
    expect(raw.users.list).to equal(payload)
  end

  it "does not replay a mutation when typed mapping fails" do
    expect(transport).to receive(:post).with("tasks", "add", anything).once.and_return("task" => { "id" => "bad" })
    expect { client.tasks.create(name: "Synthetic") }.to raise_error(FivePM::ProtocolError)
  end

  it "does not replay a data-wrapped mutation when typed mapping fails" do
    expect(transport).to receive(:post).with("tasks", "add", anything).once.and_return("data" => { "id" => "bad" })
    expect { client.tasks.create(name: "Synthetic") }.to raise_error(FivePM::ProtocolError)
  end

  it "clears the session if a sign-out response cannot be mapped" do
    client.sign_in
    expect(transport).to receive(:post).with("authentication", "signOut", anything)
                                       .and_return("signOutState" => "unexpected")
    expect { client.sign_out }.to raise_error(FivePM::ProtocolError)
    expect(client.sign_out).to be(false)
  end

  it "rejects unsupported response modes during configuration" do
    expect { FivePM::Client.new(**options, response_mode: :guess) }.to raise_error(FivePM::ConfigurationError)
  end
end
