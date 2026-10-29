require "spec_helper"

RSpec.describe FivePM::Transport do
  let(:transport) { described_class.new(host: "example.5pmweb.com") }
  let(:http) { instance_double(Net::HTTP) }
  let(:response) { instance_double(Net::HTTPResponse, code: "200", body: '{"list":[],"unknown":true}') }

  before do
    allow(Addrinfo).to receive(:getaddrinfo).and_return([double(ip_address: "8.8.8.8")])
    allow(Net::HTTP).to receive(:new).with("example.5pmweb.com", 443, nil).and_return(http)
    %i[ipaddr= use_ssl= verify_mode= max_retries= open_timeout= read_timeout= write_timeout=].each do |setter|
      allow(http).to receive(setter)
    end
    allow(http).to receive(:start).and_yield(http)
    allow(response).to receive(:[]).and_return(nil)
    allow(response).to receive(:read_body) { |&block| block.call(response.body) }
    allow(http).to receive(:request).and_yield(response)
  end

  it "pins DNS, verifies TLS, disables proxies and retries, and sets timeouts" do
    expect(http).to receive(:ipaddr=).with("8.8.8.8")
    expect(http).to receive(:use_ssl=).with(true)
    expect(http).to receive(:verify_mode=).with(OpenSSL::SSL::VERIFY_PEER)
    expect(http).to receive(:max_retries=).with(0)
    expect(http).to receive(:open_timeout=).with(5)
    expect(http).to receive(:read_timeout=).with(30)
    expect(http).to receive(:write_timeout=).with(30)
    expect(transport.post("projects", "getAll", {})).to eq("list" => [], "unknown" => true)
  end

  it "encodes nested forms and secrets in the body, keeping the URL clean" do
    expect(http).to receive(:request) do |request, &block|
      expect(request).to be_a(Net::HTTP::Post)
      expect(request.path).to eq("/api/v2/service/post/tasks/add")
      expect(request["content-type"]).to eq("application/x-www-form-urlencoded")
      expect(request["accept"]).to eq("application/json")
      expect(URI.decode_www_form(request.body).to_h).to eq(
        "task[name]" => "A&B + test", "task[hidden]" => "false", "task[team][0][id]" => "12",
        "sessionId" => "synthetic-secret", "retType" => "json"
      )
      block.call(response)
    end
    transport.post("tasks", "add", { "task" => { "name" => "A&B + test", "hidden" => false,
                                                 "team" => [{ "id" => 12 }], "missing" => nil },
                                     "sessionId" => "synthetic-secret" })
  end

  it "rejects non-account hostnames, URL components and lookalike domains" do
    [nil, "localhost", "127.0.0.1", "https://a.5pmweb.com", "a.5pmweb.com.evil.test", "a.5pmweb.com/path",
     "a.5pmweb.com:443", "a@b.5pmweb.com", "a.b.5pmweb.com", "-a.5pmweb.com", "a.5pmweb.com\n"].each do |host|
      expect { described_class.new(host: host) }.to raise_error(FivePM::ConfigurationError)
    end
  end

  it "validates all timeout values" do
    [0, -1, nil, "5", Float::INFINITY, Float::NAN].each do |value|
      %i[open_timeout read_timeout write_timeout].each do |name|
        expect { described_class.new(host: "example.5pmweb.com", **{ name => value }) }.to raise_error(FivePM::ConfigurationError)
      end
    end
  end

  it "rejects private, reserved, mixed and empty DNS results before connecting" do
    [[], ["127.0.0.1"], ["169.254.169.254"], ["10.1.1.1"], ["192.168.1.1"], ["8.8.8.8", "172.16.0.1"],
     ["100.64.0.1"], ["0.0.0.0"], ["224.0.0.1"]].each do |addresses|
      allow(Addrinfo).to receive(:getaddrinfo).and_return(addresses.map { |ip| double(ip_address: ip) })
      expect(Net::HTTP).not_to receive(:new)
      expect { transport.post("projects", "getAll", {}) }.to raise_error(FivePM::ConfigurationError)
    end
  end

  it "does not follow redirects or include server error bodies in exceptions" do
    %w[301 302 429 500].each do |status|
      allow(response).to receive(:code).and_return(status)
      allow(response).to receive(:body).and_return("secret-server-response")
      expect { transport.post("tasks", "add", {}) }.to raise_error(FivePM::HTTPError) do |error|
        expect(error.status).to eq(status.to_i)
        expect(error.message).not_to include("secret")
      end
    end
  end

  it "maps authentication statuses without exposing server bodies" do
    %w[401 403].each do |status|
      allow(response).to receive(:code).and_return(status)
      expect { transport.post("projects", "getAll", {}) }.to raise_error(FivePM::AuthenticationError)
    end
  end

  it "redacts parser exception details and causes" do
    allow(response).to receive(:body).and_return("secret invalid JSON")
    expect { transport.post("projects", "getAll", {}) }.to raise_error(FivePM::ProtocolError) do |error|
      expect(error.message).not_to include("secret")
      expect(error.cause).to be_nil
    end
  end

  it "redacts network exception details and causes without retrying" do
    [SocketError, IOError, Errno::ECONNRESET, Net::ReadTimeout, OpenSSL::SSL::SSLError].each do |error_type|
      allow(http).to receive(:request).and_raise(error_type, "synthetic-secret")
      expect { transport.post("projects", "getAll", {}) }.to raise_error(FivePM::TransportError) do |error|
        expect(error.message).not_to include("synthetic-secret")
        expect(error.cause).to be_nil
      end
    end
  end

  it "redacts transport inspection" do
    expect(transport.inspect).to eq("#<FivePM::Transport>")
  end
end

RSpec.describe "transport operation validation" do
  it "rejects unknown services and operation paths before DNS or HTTP" do
    transport = FivePM::Transport.new(host: "example.5pmweb.com")
    expect(Addrinfo).not_to receive(:getaddrinfo)
    expect { transport.post("tasks/../../internal", "add", {}) }.to raise_error(ArgumentError)
    expect { transport.post("activity", "getResizeImg", {}) }.to raise_error(ArgumentError)
  end
end

RSpec.describe "streaming response limits and HTTP errors" do
  let(:http) { instance_double(Net::HTTP) }
  let(:response) { instance_double(Net::HTTPResponse, code: "200") }
  let(:transport) { FivePM::Transport.new(host: "example.5pmweb.com", max_response_bytes: 16) }

  before do
    allow(Addrinfo).to receive(:getaddrinfo).and_return([double(ip_address: "8.8.8.8")])
    allow(Net::HTTP).to receive(:new).and_return(http)
    %i[ipaddr= use_ssl= verify_mode= max_retries= open_timeout= read_timeout= write_timeout=].each do |setter|
      allow(http).to receive(setter)
    end
    allow(http).to receive(:start).and_yield(http)
    allow(http).to receive(:request).and_yield(response)
    allow(response).to receive(:[]).and_return(nil)
  end

  it "assembles streamed JSON and aborts before buffering oversized bodies" do
    allow(response).to receive(:read_body).and_yield('{"id":').and_yield("7}")
    expect(transport.post("tasks", "getById", "id" => 7)).to eq("id" => 7)
    allow(response).to receive(:read_body).and_yield("x" * 17)
    expect { transport.post("tasks", "getById", "id" => 7) }.to raise_error(FivePM::ProtocolError, /size limit/)
  end

  it "exposes safe rate limit metadata without response bodies" do
    allow(response).to receive(:code).and_return("429")
    [nil, "5", "Wed, 29 Oct 2026 10:00:00 GMT", "secret"].each do |header|
      allow(response).to receive(:[]).with("Retry-After").and_return(header)
      expect(response).not_to receive(:read_body)
      expect { transport.post("tasks", "getById", "id" => 7) }.to raise_error(FivePM::RateLimitError) do |error|
        expect(error.retry_after).to eq(header == "5" ? 5 : nil)
        expect(error.retryable?).to eq(header.nil? || header == "5")
        expect(error.message).not_to include("secret")
      end
    end
  end

  it "classifies not-found and server statuses" do
    allow(response).to receive(:code).and_return("404")
    expect { transport.post("tasks", "getById", "id" => 7) }.to raise_error(FivePM::NotFoundError)
    allow(response).to receive(:code).and_return("503")
    expect { transport.post("tasks", "getById", "id" => 7) }.to raise_error(FivePM::ServerError)
  end

  it "validates response size and complex timeout options" do
    [nil, 0, -1, 1.5].each do |value|
      expect { FivePM::Transport.new(host: "example.5pmweb.com", max_response_bytes: value) }
        .to raise_error(FivePM::ConfigurationError)
    end
    expect { FivePM::Transport.new(host: "example.5pmweb.com", read_timeout: Complex(1, 1)) }
      .to raise_error(FivePM::ConfigurationError)
  end
end
