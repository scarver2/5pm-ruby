abort "designate a disposable tenant with FIVE_PM_SANDBOX=1 and matching FIVE_PM_SANDBOX_HOST" unless
  ENV["FIVE_PM_SANDBOX"] == "1" && ENV.fetch("FIVE_PM_HOST", "") != "" &&
  ENV["FIVE_PM_SANDBOX_HOST"] == ENV["FIVE_PM_HOST"]
abort "set FIVE_PM_ALLOW_MUTATIONS=1 for disposable mutation checks" unless ENV["FIVE_PM_ALLOW_MUTATIONS"] == "1"
require "five_pm"
require "five_pm/mcp"
require "securerandom"
require "tmpdir"

checks = []
created = []
stage = "configuration"
client = FivePM::Client.new(host: ENV.fetch("FIVE_PM_HOST"), login: ENV.fetch("FIVE_PM_LOGIN"),
                            password: ENV.fetch("FIVE_PM_PASSWORD"))
prefix = "SDK disposable validation #{SecureRandom.hex(6)}"
state_path = File.join(Dir.tmpdir, "five-pm-live-created-#{Process.pid}.json")
save = -> { File.write(state_path, JSON.generate(created)) }
validate = lambda do |service, operation, raw|
  wire = service == :project_groups ? "projectsgroups" : service.to_s
  FivePM::Response.new(raw, contract: FivePM::OPERATIONS.fetch(wire).fetch(operation))
end
add = lambda do |service, part, attributes|
  raw = client.public_send(service).create(attributes)
  wire = service == :project_groups ? "projectsgroups" : service.to_s
  record = FivePM::Envelope.parts(raw, FivePM::OPERATIONS.fetch(wire).fetch("add")).fetch(part)
  id = record.fetch("id")
  FivePM::Request.identifier!(id)
  created << { "service" => service.to_s, "id" => id }
  save.call
  response = validate.call(service, "add", raw)
  raise "create identity mismatch" unless response.public_send(part).id == Integer(id)

  id
end
remove = lambda do |service, id|
  raw = client.public_send(service).delete(id)
  raise "delete did not succeed" unless validate.call(service, "remove", raw).status

  created.reject! { |record| record["service"] == service.to_s && record["id"] == id }
  save.call
  begin
    client.public_send(service).get(id)
    raise "deleted record still exists"
  rescue FivePM::APIError
    # Missing-record codes differ by service. Final list checks also verify absence.
    nil
  end
end
begin
  stage = "project_groups.create"
  group_id = add.call(:project_groups, "group", { name: "#{prefix} group" })
  checks << stage
  stage = "project_groups.update"
  result = client.project_groups.update(id: group_id, name: "#{prefix} group updated")
  raise "group update failed" unless validate.call(:project_groups, "update",
                                                   result).group.name == "#{prefix} group updated"

  checks << stage
  stage = "projects.create"
  project_id = add.call(:projects, "project", { name: "#{prefix} project", groupId: group_id,
                                                notifyProjectTeam: false, notifyClient: false })
  checks << stage
  stage = "projects.update"
  result = client.projects.update(id: project_id, name: "#{prefix} project updated")
  raise "project update failed" unless validate.call(:projects, "update",
                                                     result).project.name == "#{prefix} project updated"

  checks << stage
  stage = "tasks.create"
  task_id = add.call(:tasks, "task", { name: "#{prefix} task", projectId: project_id,
                                       notifyProjectTeam: false, notifyTaskTeam: false, notifyClient: false })
  checks << stage
  stage = "tasks.update"
  result = client.tasks.update(id: task_id, name: "#{prefix} task updated", progress: 25)
  raise "task update failed" unless validate.call(:tasks, "update", result).task.name == "#{prefix} task updated"

  checks << stage
  stage = "activity.create"
  activity_id = add.call(:activity, "activity", { text: "#{prefix} message", projectId: project_id, taskId: task_id,
                                                  type: "msg", notifyProjectTeam: false,
                                                  notifyTaskTeam: false, notifyClient: false })
  checks << stage
  stage = "activity.update"
  result = client.activity.update(id: activity_id, text: "#{prefix} message updated")
  raise "activity update failed" unless validate.call(:activity, "update",
                                                      result).activity.text == "#{prefix} message updated"

  checks << stage
  { project_groups: [group_id, "group"], projects: [project_id, "project"], tasks: [task_id, "task"],
    activity: [activity_id, "activity"] }.each do |service, (id, part)|
    stage = "#{service}.get"
    raise "get failed" unless validate.call(service, "getById",
                                            client.public_send(service).get(id)).public_send(part).id == Integer(id)

    checks << stage
  end
  [[:activity, activity_id], [:tasks, task_id], [:projects, project_id],
   [:project_groups, group_id]].each do |service, id|
    stage = "#{service}.delete"
    remove.call(service, id)
    checks << stage
  end
  stage = "mcp.approval"
  decisions = []
  events = []
  proposals = []
  adapter = FivePM::MCPAdapter::Server.new(client: client, allow_mutations: true,
                                           approver: lambda { |proposal|
                                             unless proposal.frozen? && proposal.fetch("arguments").frozen?
                                               raise "mutable proposal"
                                             end

                                             proposals << proposal
                                             decisions.shift
                                           }, audit: ->(event) { events << event })
  rpc_id = 0
  call = lambda do |name, arguments|
    rpc_id += 1
    JSON.parse(adapter.server.handle_json(JSON.generate(jsonrpc: "2.0", id: rpc_id, method: "tools/call",
                                                        params: { name: name, arguments: arguments }))).fetch("result")
  end
  decisions << false
  denied = call.call("five_pm_create_projects", { attributes: { name: prefix } })
  raise "approval bypass" unless denied.dig("structuredContent", "error", "code") == "approval_required"

  spoof = call.call("five_pm_create_projects", { attributes: { name: prefix }, confirmed: true })
  raise "agent approval accepted" unless spoof["isError"] && proposals.length == 1

  checks << stage
  stage = "mcp.projects.create"
  decisions << true
  result = call.call("five_pm_create_projects", { attributes: { name: "#{prefix} MCP project" } })
  raise "MCP create failed" if result["isError"]

  mcp_project = result.fetch("structuredContent").fetch("data").fetch("id")
  created << { "service" => "projects", "id" => mcp_project }
  save.call
  checks << stage
  stage = "mcp.tasks.create"
  decisions << true
  result = call.call("five_pm_create_tasks",
                     { attributes: { name: "#{prefix} MCP task", projectId: Integer(mcp_project) } })
  raise "MCP task create failed" if result["isError"]

  mcp_task = result.fetch("structuredContent").fetch("data").fetch("id")
  created << { "service" => "tasks", "id" => mcp_task }
  save.call
  checks << stage
  { projects: mcp_project, tasks: mcp_task }.each do |service, id|
    stage = "mcp.#{service}.update"
    decisions << true
    result = call.call("five_pm_update_#{service}", { id: Integer(id), attributes: { name: "#{prefix} MCP updated" } })
    raise "MCP update failed" if result["isError"]

    checks << stage
    stage = "mcp.#{service}.get"
    result = call.call("five_pm_get_#{service}", { id: Integer(id) })
    raise "MCP get failed" if result["isError"]
    raise "MCP update mismatch" unless result.dig("structuredContent", "data", "name") == "#{prefix} MCP updated"

    checks << stage
  end
  [[:tasks, mcp_task], [:projects, mcp_project]].each do |service, id|
    stage = "mcp.#{service}.delete_denied"
    decisions << false
    result = call.call("five_pm_delete_#{service}", { id: Integer(id) })
    raise "cached approval reused" unless result.dig("structuredContent", "error", "code") == "approval_required"

    checks << stage
    stage = "mcp.#{service}.delete"
    decisions << true
    result = call.call("five_pm_delete_#{service}", { id: Integer(id) })
    marker = result.dig("structuredContent", "data")
    raise "MCP delete failed" unless marker == true || (marker.is_a?(Integer) && marker.positive?)

    created.reject! { |record| record["service"] == service.to_s && record["id"] == id }
    save.call
    checks << stage
  end
  stage = "mcp.audit"
  raise "unexpected audit fields" unless events.all? do |event|
    event.keys.sort == %i[outcome request_id timestamp tool]
  end
  raise "leaked audit payload" if JSON.generate(events).include?(prefix)

  checks << stage
  puts JSON.pretty_generate(result: "passed", checks: checks, cleanup: created.empty?)
rescue StandardError => e
  report = { result: "failed", stage: stage, category: e.class.name, passed: checks }
  if e.is_a?(FivePM::SchemaError)
    report[:schema_mismatch] =
      { field: e.field, expected_type: e.expected_type, actual_type: e.actual_type }
  end
  report[:api_code] = e.code if e.is_a?(FivePM::APIError)
  warn JSON.generate(report)
  exit 1
ensure
  created.reverse.dup.each do |record|
    remove.call(record.fetch("service").to_sym, record.fetch("id"))
  rescue StandardError
    warn JSON.generate(result: "cleanup_failed", service: record.fetch("service"))
  end
  File.delete(state_path) if created.empty? && File.exist?(state_path)
  begin
    client.sign_out
  rescue FivePM::Error
    warn JSON.generate(result: "cleanup_failed", stage: "authentication.signOut")
  end
end
