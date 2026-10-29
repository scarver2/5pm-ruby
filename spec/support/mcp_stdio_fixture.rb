require "five_pm/mcp"
require_relative "mcp_synthetic_transport"

client = FivePM::Client.new(host: "example.5pmweb.com", login: "synthetic-login", password: "synthetic-password-secret",
                            transport: SyntheticFivePMTransport.new, response_mode: :typed)
FivePM::MCPAdapter::Server.new(client: client, audit: ->(event) { warn(JSON.generate(event)) }).open
