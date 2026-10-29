require "spec_helper"

RSpec.describe "read-only retry policy" do
  let(:delays) { [] }
  let(:policy) { FivePM::RetryPolicy.new(max_retries: 2, sleeper: ->(delay) { delays << delay }, random: -> { 0.5 }) }

  it "retries allowlisted reads with bounded exponential backoff" do
    attempts = 0
    result = policy.call("tasks", "getList") do
      attempts += 1
      raise FivePM::ServerError, 503 if attempts < 3

      "success"
    end
    expect(result).to eq("success")
    expect(delays).to eq([0.5, 1.0])
  end

  it "honors numeric rate limits without retrying early" do
    attempts = 0
    policy.call("projects", "getById") do
      attempts += 1
      raise FivePM::RateLimitError.new(retry_after: 4) if attempts == 1
    end
    expect(delays).to eq([4])
  end

  it "never retries mutations, login, unknown operations or non-transient statuses" do
    [["tasks", "add", FivePM::ServerError.new(503)],
     ["tasks", "update", FivePM::TransportError.new],
     ["authentication", "signIn", FivePM::TransportError.new],
     ["tasks", "invented", FivePM::TransportError.new],
     ["tasks", "getById", FivePM::NotFoundError.new(404)],
     ["tasks", "getById", FivePM::AuthenticationError.new]].each do |service, operation, error|
      calls = 0
      expect do
        policy.call(service, operation) do
          calls += 1
          raise error
        end
      end.to raise_error(error.class)
      expect(calls).to eq(1)
    end
    expect(delays).to eq([])
  end

  it "bounds attempts and rejects long or unparseable Retry-After rather than retrying early" do
    calls = 0
    expect do
      policy.call("tasks", "getList") do
        calls += 1
        raise FivePM::TransportError
      end
    end
      .to raise_error(FivePM::TransportError)
    expect(calls).to eq(3)
    [FivePM::RateLimitError.new(retry_after: 31), FivePM::RateLimitError.new(retryable: false)].each do |error|
      expect { policy.call("tasks", "getList") { raise error } }.to raise_error(FivePM::RateLimitError)
    end
  end

  it "disables retries by default and validates configuration" do
    calls = 0
    expect do
      FivePM::RetryPolicy.new.call("tasks", "getList") do
        calls += 1
        raise FivePM::TransportError
      end
    end
      .to raise_error(FivePM::TransportError)
    expect(calls).to eq(1)
    [-1, 4, nil, 1.5].each do |value|
      expect { FivePM::RetryPolicy.new(max_retries: value) }.to raise_error(FivePM::ConfigurationError)
    end
    [0, -1, nil, Complex(1, 1), Float::INFINITY].each do |value|
      expect { FivePM::RetryPolicy.new(max_delay: value) }.to raise_error(FivePM::ConfigurationError)
    end
    expect(policy.inspect).to eq("#<FivePM::RetryPolicy>")
  end
end

RSpec.describe "bounded pagination" do
  let(:client) { double("client") }
  let(:resource) { FivePM::Resource.new(client, "tasks") }
  let(:page) { { "list" => { "items" => [{ "id" => "1" }, { "id" => "2" }] } } }

  it "is lazy and advances offsets by received item count" do
    expect(client).to receive(:call).with("tasks", "getList", offset: 4, count: 2, filter: { projectId: 12 })
                                    .and_return(page)
    expect(client).to receive(:call).with("tasks", "getList", offset: 6, count: 2, filter: { projectId: 12 })
                                    .and_return("list" => { "items" => [{ "id" => "3" }] })
    enumerator = resource.each_item(offset: 4, count: 2, filter: { projectId: 12 })
    expect(enumerator).to be_a(Enumerator)
    expect(enumerator.map { |item| item["id"] }).to eq(%w[1 2 3])
  end

  it "keeps typed items and yields raw envelopes when requested" do
    typed = FivePM::Response.new(page, contract: FivePM::OPERATIONS.dig("tasks", "getList"))
    expect(client).to receive(:call).with("tasks", "getList", offset: 0, count: 3).twice.and_return(typed)
    expect(resource.each_page(count: 3).first).to equal(typed)
    expect(resource.each_item(count: 3).map(&:id)).to eq([1, 2])
  end

  it "stops at empty pages and allows early termination without further requests" do
    expect(client).to receive(:call).with("tasks", "getList", offset: 0, count: 100).once
                                    .and_return("list" => { "items" => [] })
    expect(resource.each_item.to_a).to eq([])
    expect(client).to receive(:call).with("tasks", "getList", offset: 0, count: 2).once.and_return(page)
    expect(resource.each_item(count: 2).take(1)).to eq([{ "id" => "1" }])
  end

  it "rejects repeated pages, malformed envelopes and exhausted bounds" do
    allow(client).to receive(:call).and_return(page)
    expect { resource.each_page(count: 2).to_a }.to raise_error(FivePM::ProtocolError, /repeated page/)
    expect { resource.each_page(count: 1).to_a }.to raise_error(FivePM::ProtocolError, /page size/)
    expect { resource.each_page(count: 2, max_pages: 1).to_a }.to raise_error(FivePM::ProtocolError, /max_pages/)
    [[], {}, { "list" => [] }, { "list" => { "items" => nil } }].each do |bad|
      allow(client).to receive(:call).and_return(bad)
      expect { resource.each_page.to_a }.to raise_error(FivePM::ProtocolError, /list.items/)
    end
  end

  it "rejects unsupported services and invalid bounds before requesting data" do
    expect(client).not_to receive(:call)
    expect { FivePM::Resource.new(client, "users").each_page.to_a }.to raise_error(ArgumentError)
    [0, -1, nil, 10_001].each do |value|
      expect { resource.each_page(max_pages: value).to_a }.to raise_error(ArgumentError)
    end
    expect { resource.each_page(count: 0).to_a }.to raise_error(ArgumentError)
    expect { resource.each_page(offset: -1).to_a }.to raise_error(ArgumentError)
  end
end

RSpec.describe "request validation and rejected sessions" do
  let(:transport) { double("transport") }
  let(:client) do
    FivePM::Client.new(host: "example.5pmweb.com", login: "synthetic-login", password: "synthetic-password",
                       transport: transport)
  end

  it "rejects missing operation arguments and unsafe nested field names before sign-in" do
    expect(transport).not_to receive(:post)
    expect { client.tasks.get(nil) }.to raise_error(ArgumentError)
    expect { client.tasks.get("not-an-id") }.to raise_error(ArgumentError)
    expect { client.tasks.update(id: nil) }.to raise_error(ArgumentError)
    expect { client.tasks.list(filter: "bad") }.to raise_error(ArgumentError)
    expect { client.users.call("getByEmail", email: "") }.to raise_error(ArgumentError)
    expect { client.tasks.call("remove") }.to raise_error(ArgumentError)
    expect { client.users.call("getByEmail") }.to raise_error(ArgumentError)
    expect { client.activity.call("attachFiles", activityId: 2) }.to raise_error(ArgumentError)
    expect { client.tasks.create("bad") }.to raise_error(ArgumentError)
    expect { client.tasks.create("name][sessionId" => "value") }.to raise_error(ArgumentError)
    expect { client.tasks.create(1 => "value") }.to raise_error(ArgumentError)
    expect { client.tasks.create(name: Object.new) }.to raise_error(ArgumentError)
    expect { client.tasks.create(progress: Float::NAN) }.to raise_error(ArgumentError)
    expect { client.tasks.list(count: 0) }.to raise_error(ArgumentError)
    nested = {}
    nested["self"] = nested
    expect { client.tasks.create(nested) }.to raise_error(ArgumentError, /nesting/)
    expect { client.tasks.call("update", task: { name: "missing id" }) }.to raise_error(ArgumentError)
  end

  it "accepts typed models as resource attributes using their original wire values" do
    allow(transport).to receive(:post).with("authentication", "signIn", anything)
                                      .and_return("auth" => { "sessionId" => "token" })
    attributes = { "id" => "7", "name" => "Synthetic", "future" => [1.5, true, nil] }
    model = FivePM::Models::Task.new(attributes)
    expect(transport).to receive(:post).with("tasks", "update", { "task" => attributes, "sessionId" => "token" })
    client.tasks.update(model)
    expect(transport).to receive(:post).with("tasks", "add", { "task" => attributes, "sessionId" => "token" })
    client.tasks.create(model)
  end

  it "invalidates rejected sessions for the next explicit call without replaying the failed operation" do
    expect(transport).to receive(:post).with("authentication", "signIn", anything).ordered
                                       .and_return("auth" => { "sessionId" => "old" })
    expect(transport).to receive(:post).with("tasks", "remove", anything).ordered
                                       .and_raise(FivePM::AuthenticationError)
    expect(transport).to receive(:post).with("authentication", "signIn", anything).ordered
                                       .and_return("auth" => { "sessionId" => "new" })
    expect(transport).to receive(:post).with("tasks", "getById", { "id" => 7, "sessionId" => "new" }).ordered
                                       .and_return({})
    expect { client.tasks.delete(7) }.to raise_error(FivePM::AuthenticationError)
    client.tasks.get(7)
  end
end

RSpec.describe "client credential isolation" do
  it "copies configuration strings and refuses secret-bearing serialization" do
    host = +"example.5pmweb.com"
    login = +"synthetic-login"
    password = +"synthetic-password"
    transport = double("transport")
    client = FivePM::Client.new(host: host, login: login, password: password, transport: transport)
    login.replace("changed")
    password.replace("changed")
    expect(transport).to receive(:post).with("authentication", "signIn",
                                             { "login" => "synthetic-login", "password" => "synthetic-password" })
                                       .and_return("auth" => { "sessionId" => "synthetic-session" })
    client.sign_in
    expect { Marshal.dump(client) }.to raise_error(TypeError, /cannot be serialized/)
    expect(client.inspect).not_to include("synthetic")
  end
end
