abort "designate a disposable tenant with FIVE_PM_SANDBOX=1 and matching FIVE_PM_SANDBOX_HOST" unless
  ENV["FIVE_PM_SANDBOX"] == "1" && ENV.fetch("FIVE_PM_HOST", "") != "" &&
  ENV["FIVE_PM_SANDBOX_HOST"] == ENV["FIVE_PM_HOST"]
require "five_pm"
require "five_pm/mcp"
require "open3"
require "timeout"
require "rexml/document"
require "net/http"
require_relative "live_subprocess"

checks = []
stage = "configuration"
client = FivePM::Client.new(host: ENV.fetch("FIVE_PM_HOST"), login: ENV.fetch("FIVE_PM_LOGIN"),
                            password: ENV.fetch("FIVE_PM_PASSWORD"), response_mode: :typed)
begin
  %w[authentication projects tasks projectsgroups activity users].each do |service|
    stage = "contract.#{service}"
    uri = URI("https://#{ENV.fetch('FIVE_PM_HOST')}/api/v2/wsdl/#{service}.wsdl")
    result = Net::HTTP.start(uri.host, 443, nil, use_ssl: true, open_timeout: 5, read_timeout: 30) { |http| http.get(uri.path) }
    raise "contract HTTP failure" unless result.code == "200"

    document = REXML::Document.new(result.body)
    ns = { "w" => "http://schemas.xmlsoap.org/wsdl/" }
    binding = REXML::XPath.first(document, "//w:binding[contains(@name,'HttpPost')]", ns)
    supported = binding.get_elements("operation").map { |node| node.attributes["name"] }
    inventory = {}
    supported.each do |operation|
      parts = %w[Request Response].map do |suffix|
        message = REXML::XPath.first(document, "//w:message[@name='#{operation}HttpPost#{suffix}']", ns)
        message.elements.to_a.to_h { |part| [part.attributes["name"], part.attributes["type"]] }
      end
      inventory[operation] = { "parameters" => parts[0], "response" => parts[1] }
    end
    raise "contract mismatch" unless inventory == FivePM::OPERATIONS.fetch(service)

    checks << stage
  end
  stage = "contract.schema"
  uri = URI("https://#{ENV.fetch('FIVE_PM_HOST')}/api/v2/wsdl/schema.xsd")
  result = Net::HTTP.start(uri.host, 443, nil, use_ssl: true, open_timeout: 5, read_timeout: 30) { |http| http.get(uri.path) }
  raise "schema HTTP failure" unless result.code == "200"

  document = REXML::Document.new(result.body)
  ns = { "x" => "http://www.w3.org/2001/XMLSchema" }
  types = {}
  REXML::XPath.each(document, "//x:complexType", ns) do |node|
    name = node.attributes["name"]
    next if name.end_with?("Filter")

    types[name] = REXML::XPath.match(node, "x:sequence/x:element", ns).to_h do |field|
      [field.attributes["name"], { "type" => field.attributes["type"].split(":").last,
                                   "repeated" => field.attributes["maxOccurs"] == "unbounded" }]
    end
  end
  raise "schema mismatch" unless types == FivePM::Models::TYPES

  checks << stage
  stage = "authentication.authorized_user"
  raise "missing user" unless client.authentication.authorized_user.user.id.positive?

  checks << stage
  stage = "authentication.nop"
  nop = client.authentication.call("nop")
  raise "invalid nop response" unless [nil, true, false].include?(nop.nop_state)

  checks << stage
  stage = "authentication.isSsl"
  raise "SSL failed" unless client.authentication.ssl?.is_ssl

  checks << stage
  %i[projects project_groups tasks activity users].each do |service|
    stage = "#{service}.list"
    resource = client.public_send(service)
    response = %i[users project_groups].include?(service) ? resource.list : resource.list(count: 2)
    items = response.list.items
    raise "invalid list" unless items.is_a?(Array)

    checks << stage
    unless items.empty?
      stage = "#{service}.get"
      part = { projects: :project, project_groups: :group, tasks: :task, activity: :activity,
               users: :user }.fetch(service)
      raise "wrong get identifier" unless resource.get(items.first.id).public_send(part).id == items.first.id

      checks << stage
    end
    next if %i[users project_groups].include?(service)

    stage = "#{service}.pagination"
    resource.each_page(count: 1, max_pages: 100).take(2).each do |page|
      raise "oversized page" unless page.list.items.length <= 1
    end
    checks << stage
  end
  stage = "projects.getAll"
  raise "missing project list" unless client.projects.call("getAll").list.items.is_a?(Array)

  checks << stage
  stage = "users.getAuthorizedUser"
  raise "missing user" unless client.users.call("getAuthorizedUser").user.id.positive?

  checks << stage
  stage = "users.find_by_email"
  raise "missing email result" unless client.users.find_by_email(ENV.fetch("FIVE_PM_LOGIN")).user.id.positive?

  checks << stage
  stage = "activity.files"
  raise "missing files list" unless client.activity.files(count: 1).list.items.is_a?(Array)

  checks << stage
  stage = "mcp.stdio"
  requests = [{ jsonrpc: "2.0", id: 1, method: "initialize", params: { protocolVersion: "2025-11-25", capabilities: {},
                                                                       clientInfo: { name: "live-validation",
                                                                                     version: "1" } } },
              { jsonrpc: "2.0", method: "notifications/initialized" },
              { jsonrpc: "2.0", id: 2, method: "tools/list" }]
  %w[projects tasks activity project_groups users].each_with_index do |service, index|
    requests << { jsonrpc: "2.0", id: index + 3, method: "tools/call",
                  params: { name: "five_pm_list_#{service}", arguments: { limit: 1 } } }
  end
  requests << { jsonrpc: "2.0", id: 8, method: "tools/call",
                params: { name: "five_pm_delete_tasks", arguments: { id: 1, confirmed: true } } }
  stdout, stderr, status = LiveSubprocess.capture(
    {}, RbConfig.ruby, "-Ilib", "-Imcp/lib", "-r", "./spec/support/live_operation_audit",
    "mcp/exe/five-pm-mcp", timeout: 120,
                           stdin_data: "#{requests.map { |request| JSON.generate(request) }.join("\n")}\n"
  )
  raise "stdio process failed" unless status.success?

  responses = stdout.lines.map { |line| JSON.parse(line) }.to_h { |response| [response.fetch("id"), response] }
  raise "wrong tools" unless responses.dig(2, "result", "tools").length == 10

  (3..7).each { |id| raise "live MCP read failed" unless responses.dig(id, "result", "isError") == false }
  raise "default mutation allowed" unless responses.fetch(8).key?("error")

  events = stderr.lines.map { |line| JSON.parse(line) }
  raise "unexpected audit fields" unless events.all? do |event|
    event.keys.sort == %w[outcome request_id timestamp tool]
  end
  raise "unexpected audit outcomes" unless events.map do |event|
    event.fetch("outcome")
  end == %w[success success success success success rejected]

  checks << stage
  stage = "cleanup.no_disposable_records"
  %i[projects tasks activity project_groups users].each do |service|
    resource = client.public_send(service)
    items = if %i[project_groups users].include?(service)
              resource.list.list.items
            else
              resource.each_item(count: 100, max_pages: 100).to_a
            end
    raise "disposable records remain" if items.any? do |item|
      [item["name"], item["firstName"], item["text"]].any? { |value| value.to_s.start_with?("SDK disposable ") }
    end
  end
  checks << stage
  puts JSON.pretty_generate(result: "passed", checks: checks, mutations_tested: false)
rescue StandardError => e
  report = { result: "failed", stage: stage, category: e.class.name, passed: checks }
  if e.is_a?(FivePM::SchemaError)
    report[:schema_mismatch] =
      { field: e.field, expected_type: e.expected_type, actual_type: e.actual_type }
  end
  warn JSON.generate(report)
  exit 1
ensure
  begin
    client.sign_out
  rescue FivePM::Error
    warn JSON.generate(result: "cleanup_failed", stage: "authentication.signOut")
  end
end
