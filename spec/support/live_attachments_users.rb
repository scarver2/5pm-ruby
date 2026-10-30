abort "designate a disposable tenant with FIVE_PM_SANDBOX=1 and matching FIVE_PM_SANDBOX_HOST" unless
  ENV["FIVE_PM_SANDBOX"] == "1" && ENV.fetch("FIVE_PM_HOST", "") != "" &&
  ENV["FIVE_PM_SANDBOX_HOST"] == ENV["FIVE_PM_HOST"]
abort "set FIVE_PM_ALLOW_MUTATIONS=1 for disposable mutation checks" unless ENV["FIVE_PM_ALLOW_MUTATIONS"] == "1"
require "five_pm"
require "securerandom"
client = FivePM::Client.new(host: ENV.fetch("FIVE_PM_HOST"), login: ENV.fetch("FIVE_PM_LOGIN"),
                            password: ENV.fetch("FIVE_PM_PASSWORD"))
created = []
checks = []
stage = "configuration"
prefix = "SDK disposable extra #{SecureRandom.hex(6)}"
begin
  stage = "users.create"
  result = client.users.create(firstName: prefix, lastName: "Test", email: "sdk-#{SecureRandom.hex(6)}@example.invalid",
                               password: "#{SecureRandom.hex(6)}Aa!", securityLevel: "user")
  user_id = result.fetch("data").fetch("id")
  created << [:users, user_id]
  checks << stage
  stage = "users.update"
  result = client.users.update(id: user_id, lastName: "Updated")
  response = FivePM::Response.new(result, contract: FivePM::OPERATIONS.dig("users", "update"))
  raise "user update failed" unless response.user.last_name == "Updated"

  checks << stage
  stage = "users.get"
  response = FivePM::Response.new(client.users.get(user_id), contract: FivePM::OPERATIONS.dig("users", "getById"))
  raise "user get failed" unless response.user.id == Integer(user_id)

  checks << stage
  stage = "users.delete"
  result = client.users.delete(user_id)
  raise "user deletion missing data" unless result.key?("data")

  created.delete([:users, user_id])
  checks << stage
  stage = "attachment.setup"
  project_id = client.projects.create(name: prefix).fetch("data").fetch("id")
  created << [:projects, project_id]
  task_id = client.tasks.create(name: prefix, projectId: project_id).fetch("data").fetch("id")
  created << [:tasks, task_id]
  activity_id = client.activity.create(type: "msg", taskId: task_id, text: prefix).fetch("data").fetch("id")
  created << [:activity, activity_id]
  stage = "activity.attach_files"
  text = "SDK disposable attachment verification\n"
  client.activity.attach_files(activity_id: activity_id,
                               files: { "items" => [{ "name" => "sdk-probe.txt", "type" => "file",
                                                      "size" => text.bytesize,
                                                      "content" => [text].pack("m0") }] })
  checks << stage
  stage = "activity.files"
  response = FivePM::Response.new(client.activity.files(filter: { taskId: task_id }),
                                  contract: FivePM::OPERATIONS.dig("activity", "getFilesList"))
  files = response.list.items
  raise "expected one attachment" unless files.length == 1

  file_id = files.first.id
  checks << stage
  stage = "activity.download_file"
  result = client.activity.download_file(file_id)
  content = result.bytes
  raise "download content mismatch" unless content == text

  checks << stage
  stage = "activity.delete_file"
  client.activity.delete_file(file_id)
  checks << stage
  puts JSON.pretty_generate(result: "passed", checks: checks)
rescue StandardError => e
  report = { result: "failed", stage: stage, category: e.class.name, passed: checks }
  report[:api_code] = e.code if e.is_a?(FivePM::APIError)
  if e.is_a?(FivePM::SchemaError)
    report[:schema_mismatch] =
      { field: e.field, expected_type: e.expected_type, actual_type: e.actual_type }
  end
  warn JSON.generate(report)
  exit 1
ensure
  created.reverse_each do |service, id|
    client.public_send(service).delete(id)
  rescue StandardError
    warn JSON.generate(result: "cleanup_failed", service: service)
  end
  begin
    client.sign_out
  rescue FivePM::Error
    warn JSON.generate(result: "cleanup_failed", stage: "authentication.signOut")
  end
end
