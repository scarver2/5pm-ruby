# spec/support/live_plan.rb
# frozen_string_literal: true

# Orders the opt-in live suites and stops later write suites after the first failure.
# The final read-only leftover scan still runs so a failed run reports what remains.
module LivePlan
  WRITE_SUITES = %w[live_mutations live_attachments live_users].freeze
  # A standard User cannot modify or remove other profiles, so these operations are
  # verified only by the Administrator-gated User suite.
  USER_ADMIN_OPERATIONS = %w[users.add users.remove users.update].freeze

  def self.suites(mutations:, user_admin:)
    return %w[live_reads] unless mutations

    suites = %w[live_reads live_mutations live_attachments]
    suites << "live_users" if user_admin
    suites << "live_cleanup"
  end

  def self.excluded_operations(mutations:, user_admin:)
    mutations && !user_admin ? USER_ADMIN_OPERATIONS : []
  end

  def self.run(suites)
    failed = nil
    suites.map do |suite|
      if failed && WRITE_SUITES.include?(suite)
        { check: suite, passed: false, skipped: true, skipped_after: failed, diagnostics: [] }
      else
        report = yield(suite)
        failed ||= suite unless report.fetch(:passed)
        report
      end
    end
  end
end
