require "five_pm"

# Environment variables can be injected by Infisical or another process secret provider.
client = FivePM::Client.new(host: ENV.fetch("FIVE_PM_HOST"), login: ENV.fetch("FIVE_PM_LOGIN"),
                            password: ENV.fetch("FIVE_PM_PASSWORD"), response_mode: :typed)
begin
  # One bounded request; returned account content may be sensitive.
  response = client.tasks.list(filter: { projectId: Integer(ENV.fetch("FIVE_PM_PROJECT_ID")) }, count: 20)
  response.list.each { |task| puts "#{task.id}: #{task.name}" }
ensure
  client.sign_out
end
