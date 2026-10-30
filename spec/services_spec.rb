require "spec_helper"

RSpec.describe "service-specific operations" do
  let(:client) { double("client") }

  it "uses verified authentication and user operations" do
    auth = FivePM::Authentication.new(client, "authentication")
    users = FivePM::Users.new(client, "users")
    expect(client).to receive(:call).with("authentication", "getAuthorizedUser")
    expect(client).to receive(:call).with("authentication", "isSsl")
    expect(client).to receive(:call).with("users", "getByEmail", email: "synthetic@example.com")
    auth.authorized_user
    auth.ssl?
    users.find_by_email("synthetic@example.com")
  end

  it "preserves attachment inputs and downloads through the bounded binary helper" do
    resource = FivePM::Activity.new(client, "activity")
    files = { "items" => [{ "name" => "synthetic.txt", "content" => "synthetic" }] }
    expect(client).to receive(:call).with("activity", "attachFiles", activityId: 7, files: files).twice
    resource.attach_files(activity_id: 7, files: files)
    resource.attach_files(activity_id: 7, files: FivePM::Models::FileList.new(files))
    expect { resource.attach_files(activity_id: 7, files: []) }.to raise_error(ArgumentError)
    expect(client).to receive(:call).with("activity", "getFilesList", filter: { taskId: 8 }, offset: 0, count: 10)
    resource.files(filter: { taskId: 8 }, offset: 0, count: 10)
    expect(client).to receive(:call).with("activity", "removeFile", id: 9)
    resource.delete_file(9)
    expect(client).to receive(:download_file).with(9)
    resource.download_file(9)
  end

  it "keeps sandbox checks inert unless explicitly enabled" do
    require "open3"
    script = File.join(__dir__, "../bin/sandbox-check")
    output, status = Open3.capture2e({ "FIVE_PM_SANDBOX" => nil }, RbConfig.ruby, script)
    expect(status).not_to be_success
    expect(output).to include("FIVE_PM_SANDBOX=1")
    output, status = Open3.capture2e({ "FIVE_PM_SANDBOX" => "1", "FIVE_PM_HOST" => "example.5pmweb.com",
                                       "FIVE_PM_SANDBOX_HOST" => "other.5pmweb.com" }, RbConfig.ruby, script)
    expect(status).not_to be_success
    expect(output).to include("must match")
  end

  it "gates the full live suite and requires separate mutation enablement" do
    require "open3"
    script = File.join(__dir__, "../bin/live-check")
    output, status = Open3.capture2e({ "FIVE_PM_SANDBOX" => nil }, RbConfig.ruby, script)
    expect(status).not_to be_success
    expect(output).to include("designate a disposable tenant")
    environment = { "FIVE_PM_SANDBOX" => "1", "FIVE_PM_HOST" => "synthetic.5pmweb.com",
                    "FIVE_PM_SANDBOX_HOST" => "synthetic.5pmweb.com", "FIVE_PM_ALLOW_MUTATIONS" => nil }
    output, status = Open3.capture2e(environment, RbConfig.ruby, script, "--mutations")
    expect(status).not_to be_success
    expect(output).to include("FIVE_PM_ALLOW_MUTATIONS=1")
  end
end
