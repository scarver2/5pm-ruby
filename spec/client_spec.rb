require "spec_helper"

RSpec.describe FivePM::Client do
  let(:transport) { double("transport") }
  let(:token) { { "auth" => { "sessionId" => "synthetic-session" } } }
  let(:options) do
    { host: "example.5pmweb.com", login: "synthetic@example.com", password: "test-password", transport: transport }
  end
  let(:client) { described_class.new(**options) }

  def expect_login
    expect(transport).to receive(:post).with("authentication", "signIn", {
                                               "login" => "synthetic@example.com", "password" => "test-password"
                                             }).and_return(token)
  end

  it "preserves complete responses and nested unknown fields" do
    expect_login
    response = { "list" => [{ "id" => 123, "futureField" => { "value" => true } }], "futureEnvelope" => 7 }
    expect(transport).to receive(:post).with("tasks", "getList", {
                                               "filter" => { "projectId" => 123 },
                                               "count" => 20, "sessionId" => "synthetic-session"
                                             }).and_return(response)
    expect(client.tasks.call("getList", filter: { "projectId" => 123 }, count: 20)).to equal(response)
  end

  it "reuses a session" do
    expect_login
    expect(transport).to receive(:post).with("projects", "getAll",
                                             { "sessionId" => "synthetic-session" }).twice.and_return({})
    2.times { client.projects.call("getAll") }
  end

  it "refreshes at the conservative expiry boundary" do
    time = 0
    configured = described_class.new(**options, clock: -> { time })
    expect(transport).to receive(:post).with("authentication", "signIn", anything).twice.and_return(token)
    allow(transport).to receive(:post).with("projects", "getAll", anything).and_return({})
    configured.projects.call("getAll")
    time = 1769
    configured.projects.call("getAll")
    time = 1770
    configured.projects.call("getAll")
  end

  it "signs in only once when concurrent callers need a session" do
    expect_login
    allow(transport).to receive(:post).with("projects", "getAll", anything).and_return({})
    threads = 12.times.map { Thread.new { client.projects.call("getAll") } }
    threads.each(&:value)
  end

  it "does not retry mutations or authentication failures" do
    expect_login
    expect(transport).to receive(:post).with("tasks", "add", anything).once.and_raise(FivePM::AuthenticationError,
                                                                                      "failed")
    expect { client.tasks.call("add", task: { name: "synthetic" }) }.to raise_error(FivePM::AuthenticationError)
  end

  it "does not expose credentials through inspection" do
    expect(client.inspect).to eq("#<FivePM::Client>")
    expect(client.tasks.inspect).to eq("#<FivePM::Service tasks>")
  end

  it "exposes all six service objects" do
    expect(FivePM::SERVICE_NAMES.keys.map { |name| client.public_send(name) }).to all(be_a(FivePM::Service))
  end

  it "rejects unsupported operations, parameters and session overrides before I/O" do
    expect(transport).not_to receive(:post)
    expect { client.tasks.call("invented") }.to raise_error(ArgumentError)
    expect { client.tasks.call("getList", sessionId: "override") }.to raise_error(ArgumentError)
    expect { client.tasks.call("getList", retType: "xml") }.to raise_error(ArgumentError)
    expect { client.call("../../internal", "getAll") }.to raise_error(ArgumentError)
    %w[signIn signOut].each do |operation|
      expect { client.authentication.call(operation) }.to raise_error(ArgumentError, /sign_in or Client#sign_out/)
    end
  end

  it "supports explicit sign-in and sign-out" do
    expect_login
    expect(client.sign_in).to equal(client)
    expect(transport).to receive(:post).with("authentication", "signOut",
                                             { "sessionId" => "synthetic-session" }).and_return(true)
    expect(client.sign_out).to be(true)
    expect(client.sign_out).to be(false)
  end

  it "clears the local session even if sign-out fails" do
    expect_login
    client.sign_in
    expect(transport).to receive(:post).with("authentication", "signOut", anything).and_raise(FivePM::TransportError)
    expect { client.sign_out }.to raise_error(FivePM::TransportError)
    expect(client.sign_out).to be(false)
  end

  it "replaces a session on explicit sign-in" do
    expect(transport).to receive(:post).with("authentication", "signIn", anything).twice.and_return(token)
    2.times { client.sign_in }
  end

  it "rejects unverified or malformed auth envelopes without leaking their contents" do
    [nil, [], "secret", {}, { "auth" => "secret" }, { "auth" => { "sessionId" => "" } }].each do |response|
      allow(transport).to receive(:post).and_return(response)
      expect do
        client.sign_in
      end.to raise_error(FivePM::ProtocolError, "5pm signIn response did not contain auth.sessionId")
    end
  end

  it "allows unauthenticated isSsl without sending credentials" do
    expect(transport).to receive(:post).with("authentication", "isSsl", {}).and_return(true)
    expect(client.authentication.call("isSsl")).to be(true)
  end

  it "validates credentials and host even with an injected transport" do
    [nil, "", 1].each do |value|
      expect { described_class.new(**options, login: value) }.to raise_error(FivePM::ConfigurationError)
      expect { described_class.new(**options, password: value) }.to raise_error(FivePM::ConfigurationError)
    end
    expect { described_class.new(**options, host: "localhost") }.to raise_error(FivePM::ConfigurationError)
  end
end
