# Run under `rbs test`; never connects to an account.
require "five_pm/mcp"

class SignatureTransport
  def post(service, operation, _parameters)
    return { "data" => { "sessionId" => "synthetic-token" } } if operation == "signIn"
    return { "data" => true } if operation == "signOut"
    return { "data" => { "id" => "7", "canViewProfiles" => true } } if operation == "getAuthorizedUser"
    return { "data" => { "id" => "7", "name" => "Synthetic" } } if service == "tasks" && operation == "getById"

    { "data" => { "items" => [{ "id" => "7", "name" => "Synthetic" }], "count" => 1, "total" => 1 } }
  end

  def download_file(_parameters)
    FivePM::Download.new(bytes: "synthetic\x00bytes", content_type: "application/octet-stream")
  end
end

client = FivePM::Client.new(host: "synthetic.5pmweb.com", login: "synthetic", password: "synthetic",
                            response_mode: :typed, transport: SignatureTransport.new)
begin
  raise "typed record mismatch" unless client.tasks.get(7).task.id == 7
  raise "typed list mismatch" unless client.tasks.list(count: 2).list.map(&:id) == [7]
  raise "pagination mismatch" unless client.tasks.each_item(count: 2).map(&:id) == [7]
  raise "live boolean mismatch" unless client.authentication.authorized_user.user.can_view_profiles == true
  raise "binary mismatch" unless client.activity.download_file(7).bytes == "synthetic\x00bytes"

  events = []
  adapter = FivePM::MCPAdapter::Server.new(client: client, allow_mutations: true,
                                           approver: ->(_proposal) { false }, audit: ->(event) { events << event })
  request = JSON.generate(jsonrpc: "2.0", id: 1, method: "tools/call",
                          params: { name: "five_pm_delete_tasks", arguments: { id: 7 } })
  result = JSON.parse(adapter.server.handle_json(request))
  raise "approval mismatch" unless result.dig("result", "structuredContent", "error", "code") == "approval_required"
  raise "audit mismatch" unless events.first.fetch(:outcome) == "denied"
ensure
  client.sign_out
end
