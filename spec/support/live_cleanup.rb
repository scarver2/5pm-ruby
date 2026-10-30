abort "designate a disposable tenant with FIVE_PM_SANDBOX=1 and matching FIVE_PM_SANDBOX_HOST" unless
  ENV["FIVE_PM_SANDBOX"] == "1" && ENV.fetch("FIVE_PM_HOST", "") != "" &&
  ENV["FIVE_PM_SANDBOX_HOST"] == ENV["FIVE_PM_HOST"]
require "five_pm"

client = FivePM::Client.new(host: ENV.fetch("FIVE_PM_HOST"), login: ENV.fetch("FIVE_PM_LOGIN"),
                            password: ENV.fetch("FIVE_PM_PASSWORD"), response_mode: :typed)
begin
  %i[projects tasks activity project_groups users].each do |service|
    resource = client.public_send(service)
    items = if %i[project_groups users].include?(service)
              resource.list.list.items
            else
              resource.each_item(count: 100, max_pages: 100).to_a
            end
    if items.any? { |item| %w[name firstName text].any? { |field| item[field].to_s.start_with?("SDK disposable ") } }
      raise FivePM::ProtocolError, "disposable records remain"
    end
  end
  puts JSON.generate(result: "passed", cleanup_verified: true)
rescue FivePM::Error
  warn JSON.generate(result: "failed", stage: "cleanup.no_disposable_records")
  exit 1
ensure
  begin
    client.sign_out
  rescue FivePM::Error
    warn JSON.generate(result: "cleanup_failed", stage: "authentication.signOut")
  end
end
