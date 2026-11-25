# spec/support/live_users.rb
# frozen_string_literal: true

# Opt-in User-management qualification. 5PM's documented roles let a standard User
# add users but not modify or remove other profiles, so this suite needs an
# Administrator on a disposable tenant and runs only with FIVE_PM_LIVE_USER_ADMIN=1.
# Without that flag it creates nothing: a create-only run would leak a test User.
abort "designate a disposable tenant with FIVE_PM_SANDBOX=1 and matching FIVE_PM_SANDBOX_HOST" unless
  ENV["FIVE_PM_SANDBOX"] == "1" && ENV.fetch("FIVE_PM_HOST", "") != "" &&
  ENV["FIVE_PM_SANDBOX_HOST"] == ENV["FIVE_PM_HOST"]
abort "set FIVE_PM_ALLOW_MUTATIONS=1 for disposable mutation checks" unless ENV["FIVE_PM_ALLOW_MUTATIONS"] == "1"
abort "set FIVE_PM_LIVE_USER_ADMIN=1 with an Administrator account for User checks" unless
  ENV["FIVE_PM_LIVE_USER_ADMIN"] == "1"
require "five_pm"
require "securerandom"
require_relative "live_cleanup_ledger"
require_relative "live_record_checks"

SUITE = "live_users"
ADMIN_SECURITY_LEVEL = "0"
client = FivePM::Client.new(host: ENV.fetch("FIVE_PM_HOST"), login: ENV.fetch("FIVE_PM_LOGIN"),
                            password: ENV.fetch("FIVE_PM_PASSWORD"))
created = []
checks = []
stage = "configuration"
prefix = "SDK disposable extra #{SecureRandom.hex(6)}"
ledger = nil
remove = lambda do |id|
  LiveRecordChecks.cleanup!(client.users, id: id, contract: FivePM::OPERATIONS.dig("users", "remove"),
                                          service: :users)
end
begin
  stage = "ledger.open"
  ledger = LiveCleanupLedger.new(LiveCleanupLedger.path, host: ENV.fetch("FIVE_PM_HOST"))
  stage = "users.preflight"
  # Confirm the account can administer Users before creating one it might not delete.
  authorized = FivePM::Response.new(client.authentication.authorized_user,
                                    contract: FivePM::OPERATIONS.dig("authentication", "getAuthorizedUser")).user
  raise FivePM::ProtocolError, "User checks need an Administrator account" unless
    authorized.security_level.to_s == ADMIN_SECURITY_LEVEL

  checks << stage
  stage = "ledger.pending_cleanup"
  ledger.drain! { |service, id| service == "users" ? remove.call(id) : raise(FivePM::ProtocolError, "not a User") }
  stage = "users.create"
  result = client.users.create(firstName: prefix, lastName: "Test", email: "sdk-#{SecureRandom.hex(6)}@example.invalid",
                               password: "#{SecureRandom.hex(6)}Aa!", securityLevel: "user")
  user_id = result.fetch("data").fetch("id")
  FivePM::Request.identifier!(user_id)
  created << user_id
  ledger.record(:users, user_id, suite: SUITE)
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
  LiveRecordChecks.remove!(client.users, id: user_id, contract: FivePM::OPERATIONS.dig("users", "remove"),
                                         service: :users)
  created.delete(user_id)
  ledger.resolve(:users, user_id)
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
  created.each do |id|
    remove.call(id)
    ledger.resolve(:users, id)
  rescue StandardError
    # The ledger entry stays so the next run finishes this cleanup first.
    warn JSON.generate(result: "cleanup_failed", service: "users", retained_in_ledger: true)
  end
  begin
    client.sign_out
  rescue FivePM::Error
    warn JSON.generate(result: "cleanup_failed", stage: "authentication.signOut")
  end
end
