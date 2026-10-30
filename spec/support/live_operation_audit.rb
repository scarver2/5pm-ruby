# Loaded only by the opt-in live harness and its stdio child. No payloads or IDs.
require "five_pm"

module LiveOperationAudit
  def post(service, operation, parameters)
    result = super
    record_live_operation(service, operation)
    result
  end

  def download_file(parameters)
    result = super
    record_live_operation("activity", "downloadFile")
    result
  end

  private

  def record_live_operation(service, operation)
    return unless FivePM::OPERATIONS.dig(service, operation)

    path = ENV.fetch("FIVE_PM_LIVE_AUDIT")
    File.open(path, "a", 0o600) do |file|
      file.flock(File::LOCK_EX)
      file.puts(JSON.generate(service: service, operation: operation))
    end
  rescue SystemCallError, IOError, KeyError
    # Preserve the API result so cleanup can retain the newly created record ID.
    warn JSON.generate(result: "failed", stage: "operation_audit")
  end
end

FivePM::Transport.prepend(LiveOperationAudit) if ENV["FIVE_PM_LIVE_AUDIT"]
