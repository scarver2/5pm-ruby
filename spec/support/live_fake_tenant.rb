# spec/support/live_fake_tenant.rb
# frozen_string_literal: true

# Preloaded only by offline specs that run the live User suite as a subprocess.
# Replaces the transport with an in-memory Users tenant persisted to
# FIVE_PM_FAKE_TENANT, so consecutive runs see the same records. No network is used.
# FIVE_PM_FAKE_DENY_USER_WRITES=1 makes users.update and users.remove return API
# code 8, as observed for a standard User on 2026-10-30.
require "five_pm"
require "json"

module LiveFakeTenant
  AUTHORIZED = { "id" => "1", "firstName" => "Qualification", "lastName" => "Admin", "securityLevel" => "0" }.freeze

  def post(service, operation, parameters)
    return { "data" => { "sessionId" => "fake-session" } } if [service, operation] == %w[authentication signIn]
    return { "data" => true } if [service, operation] == %w[authentication signOut]
    return { "data" => AUTHORIZED } if [service, operation] == %w[authentication getAuthorizedUser]
    raise "unconfigured fake operation #{service}.#{operation}; no network is permitted" unless service == "users"

    LiveFakeTenant.users(operation, parameters)
  end

  def download_file(*)
    raise "no network is permitted"
  end

  def self.users(operation, parameters)
    state = load
    denied = ENV["FIVE_PM_FAKE_DENY_USER_WRITES"] == "1"
    attributes = (parameters["user"] || {}).transform_keys(&:to_s)
    id = parameters["id"] || attributes["id"]
    result =
      case operation
      when "add"
        state["next_id"] += 1
        user = { "id" => state["next_id"].to_s, "firstName" => attributes["firstName"],
                 "lastName" => attributes["lastName"], "securityLevel" => "100" }
        state["users"] << user
        { "data" => user }
      when "update"
        user = state["users"].find { |record| record["id"] == id.to_s }
        if denied || user.nil?
          { "code" => 8, "message" => "[redacted]" }
        else
          user["lastName"] = attributes["lastName"]
          { "data" => user }
        end
      when "getById"
        user = state["users"].find { |record| record["id"] == id.to_s }
        user ? { "data" => user } : { "code" => 0, "message" => "[redacted]" }
      when "getAll"
        { "data" => { "items" => [AUTHORIZED, *state["users"]] } }
      when "remove"
        if denied
          { "code" => 8, "message" => "[redacted]" }
        else
          state["users"].reject! { |record| record["id"] == id.to_s }
          { "data" => true }
        end
      else
        raise "unconfigured fake operation users.#{operation}"
      end
    File.write(ENV.fetch("FIVE_PM_FAKE_TENANT"), JSON.generate(state))
    result
  end

  def self.load
    path = ENV.fetch("FIVE_PM_FAKE_TENANT")
    File.exist?(path) ? JSON.parse(File.read(path)) : { "next_id" => 100, "users" => [] }
  end
end

FivePM::Transport.prepend(LiveFakeTenant)
