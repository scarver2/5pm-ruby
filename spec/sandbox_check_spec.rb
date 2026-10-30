require "spec_helper"
require "open3"
require "tempfile"

RSpec.describe "sandbox check diagnostics" do
  it "completes every read-only check with data-wrapped responses" do
    stdout, stderr, status = sandbox_failure("never", "FivePM::ProtocolError", data_envelopes: true)
    expect(status).to be_success
    expect(stderr).to eq("")
    expect(JSON.parse(stdout)).to include("result" => "read_only_passed",
                                          "checks" => %w[authentication.getAuthorizedUser projects.list
                                                         project_groups.list tasks.list activity.list users.list])
    expect(stdout).not_to include("secret")
  end

  def sandbox_failure(operation, exception, cleanup_failure: false, sign_in_payload: nil, data_envelopes: false,
                      user_payload: nil)
    Tempfile.create(["synthetic-sandbox", ".rb"]) do |preload|
      preload.write(<<~RUBY)
        require #{File.expand_path('../lib/five_pm', __dir__).inspect}
        FivePM::Transport.class_eval do
          define_method(:post) do |_service, action, _parameters|
            raise FivePM::TransportError, "cleanup-secret" if action == "signOut" && #{cleanup_failure}
            raise #{exception} if action == #{operation.inspect}
            value = case action
                    when "signIn" then #{sign_in_payload || '{ "auth" => { "sessionId" => "token-secret" } }'}
                    when "getAuthorizedUser" then #{user_payload || '{ "user" => { "id" => 1, "canViewProfiles" => true } }'}
                    when "getList", "getAll" then { "list" => { "items" => [] } }
                    when "signOut" then { "signOutState" => true }
                    end
            #{data_envelopes} ? { "data" => value.values.first } : value
          end
        end
      RUBY
      preload.flush
      environment = { "FIVE_PM_SANDBOX" => "1", "FIVE_PM_SANDBOX_HOST" => "synthetic.5pmweb.com",
                      "FIVE_PM_HOST" => "synthetic.5pmweb.com", "FIVE_PM_LOGIN" => "login-secret",
                      "FIVE_PM_PASSWORD" => "password-secret" }
      Open3.capture3(environment, RbConfig.ruby, "-r", preload.path,
                     File.expand_path("../bin/sandbox-check", __dir__))
    end
  end

  it "identifies sign-in response failures without exposing exception messages" do
    stdout, stderr, status = sandbox_failure("signIn", 'FivePM::ProtocolError, "payload-secret"')
    expect(status).not_to be_success
    expect(stdout).to eq("")
    expect(JSON.parse(stderr.lines.first)).to include("result" => "failed", "stage" => "authentication.signIn",
                                                      "category" => "unexpected_response",
                                                      "sign_in_response" => { "response_received" => false })
    expect(stderr).not_to include("secret", "synthetic.5pmweb.com")
  end

  it "retains the failed read stage when sign-out also fails" do
    _, stderr, status = sandbox_failure("getList", "FivePM::ServerError, 503", cleanup_failure: true)
    expect(status).not_to be_success
    expect(JSON.parse(stderr.lines.first)).to eq(
      "result" => "failed", "stage" => "projects.list", "category" => "http_error", "http_status" => 503,
      "last_response" => { "operation" => "projects.getList", "response_received" => false }
    )
    expect(stderr).not_to include("secret")
  end

  it "reports only known field names and types for unexpected sign-in JSON" do
    payload = '{ "sessionId" => "token-secret", "payload-secret" => "password-secret", ' \
              '"error" => { "message" => "account-secret", "private-secret" => 42 } }'
    _, stderr, status = sandbox_failure("never", "FivePM::ProtocolError", sign_in_payload: payload)
    expect(status).not_to be_success
    expect(JSON.parse(stderr.lines.first).fetch("sign_in_response")).to eq(
      "response_received" => true,
      "shape" => { "type" => "object", "fields" => {
        "sessionId" => { "type" => "string" },
        "error" => { "type" => "object", "fields" => { "message" => { "type" => "string" } } }
      } }
    )
    expect(stderr).not_to include("secret")
  end

  it "distinguishes rejected credentials from connection failures" do
    { "FivePM::AuthenticationError" => "authentication_rejected",
      "FivePM::TransportError" => "connection_failed" }.each do |type, category|
      _, stderr, status = sandbox_failure("signIn", "#{type}, \"secret\"")
      expect(status).not_to be_success
      expect(JSON.parse(stderr.lines.first)).to include("category" => category)
      expect(stderr).not_to include("secret")
    end
  end

  it "reports schema field types without including user data" do
    payload = '{ "data" => { "id" => "private-user-secret", "email" => "private-email-secret" } }'
    stdout, stderr, status = sandbox_failure("never", "FivePM::ProtocolError", user_payload: payload)
    expect(status).not_to be_success
    expect(stdout).to eq("")
    expect(JSON.parse(stderr.lines.first)).to include(
      "stage" => "authentication.getAuthorizedUser",
      "schema_mismatch" => { "field" => "id", "expected_type" => "integer", "actual_type" => "string" }
    )
    expect(stderr).not_to include("secret")
  end
end
