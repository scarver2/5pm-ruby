# spec/support/live_attachments.rb
# frozen_string_literal: true

# Opt-in attachment qualification. Independent of User management, so a User-suite
# failure cannot hide attachment coverage.
abort "designate a disposable tenant with FIVE_PM_SANDBOX=1 and matching FIVE_PM_SANDBOX_HOST" unless
  ENV["FIVE_PM_SANDBOX"] == "1" && ENV.fetch("FIVE_PM_HOST", "") != "" &&
  ENV["FIVE_PM_SANDBOX_HOST"] == ENV["FIVE_PM_HOST"]
abort "set FIVE_PM_ALLOW_MUTATIONS=1 for disposable mutation checks" unless ENV["FIVE_PM_ALLOW_MUTATIONS"] == "1"
require "five_pm"
require "securerandom"
require_relative "live_attachment_checks"
require_relative "live_cleanup_ledger"
require_relative "live_record_checks"

SUITE = "live_attachments"
client = FivePM::Client.new(host: ENV.fetch("FIVE_PM_HOST"), login: ENV.fetch("FIVE_PM_LOGIN"),
                            password: ENV.fetch("FIVE_PM_PASSWORD"))
created = []
checks = []
stage = "configuration"
prefix = "SDK disposable attachment #{SecureRandom.hex(6)}"
ledger = nil
remove = lambda do |service, id|
  contract = FivePM::OPERATIONS.fetch(service.to_s).fetch("remove")
  LiveRecordChecks.cleanup!(client.public_send(service), id: id, contract: contract, service: service)
end
track = lambda do |service, raw|
  id = raw.fetch("data").fetch("id")
  FivePM::Request.identifier!(id)
  created << [service, id]
  ledger.record(service, id, suite: SUITE)
  id
end
begin
  stage = "ledger.open"
  ledger = LiveCleanupLedger.new(LiveCleanupLedger.path, host: ENV.fetch("FIVE_PM_HOST"))
  stage = "ledger.pending_cleanup"
  ledger.drain! { |service, id| remove.call(service.to_sym, id) }
  stage = "attachment.setup"
  project_id = track.call(:projects, client.projects.create(name: prefix, notifyProjectTeam: false,
                                                            notifyClient: false))
  task_id = track.call(:tasks, client.tasks.create(name: prefix, projectId: project_id, notifyProjectTeam: false,
                                                   notifyTaskTeam: false, notifyClient: false))
  activity_id = track.call(:activity, client.activity.create(type: "msg", taskId: task_id, text: prefix,
                                                             notifyProjectTeam: false, notifyTaskTeam: false,
                                                             notifyClient: false))
  checks << stage
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
  raise "download content mismatch" unless client.activity.download_file(file_id).bytes == text

  checks << stage
  stage = "activity.delete_file"
  LiveAttachmentChecks.remove!(client.activity, task_id: task_id, file_id: file_id)
  checks << stage
  stage = "attachment.teardown"
  created.reverse.each do |service, id|
    remove.call(service, id)
    ledger.resolve(service, id)
    created.delete([service, id])
  end
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
    remove.call(service, id)
    ledger.resolve(service, id)
  rescue StandardError
    # The ledger entry stays so the next run finishes this cleanup first.
    warn JSON.generate(result: "cleanup_failed", service: service, retained_in_ledger: true)
  end
  begin
    client.sign_out
  rescue FivePM::Error
    warn JSON.generate(result: "cleanup_failed", stage: "authentication.signOut")
  end
end
