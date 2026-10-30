require "five_pm/mcp"
require_relative "mcp_synthetic_transport"

client = FivePM::Client.new(host: "example.5pmweb.com", login: "synthetic-login", password: "synthetic-password-secret",
                            transport: SyntheticFivePMTransport.new, response_mode: :typed)
options = {}
if ARGV == ["synthetic-approvals"]
  decisions = [false, true, false]
  options = { allow_mutations: true, approver: ->(_proposal) { decisions.shift } }
end
FivePM::MCPAdapter::Server.new(client: client, audit: ->(event) { warn(JSON.generate(event)) }, **options).open
