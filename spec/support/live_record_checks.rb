require "five_pm"

module LiveRecordChecks
  # Observed missing-record codes are specific only for these services. Users and
  # groups return generic code 0, so their complete getAll lists must confirm absence.
  MISSING_CODES = { projects: 441, tasks: 441, activity: 543 }.freeze

  def self.missing?(resource, id, service:)
    resource.get(id)
    false
  rescue FivePM::APIError => e
    service = service.to_sym
    unless %i[users project_groups].include?(service)
      raise unless e.code == MISSING_CODES.fetch(service)

      return true
    end
    wire = service == :project_groups ? "projectsgroups" : "users"
    raw = resource.list
    response = if raw.is_a?(FivePM::Response)
                 raw
               else
                 FivePM::Response.new(raw,
                                      contract: FivePM::OPERATIONS.dig(wire,
                                                                       "getAll"))
               end
    items = response.list&.items
    raise FivePM::ProtocolError, "missing cleanup list" unless items.is_a?(Array)

    items.none? { |record| record.id.to_s == id.to_s }
  end

  def self.absent!(resource, id, service:)
    raise FivePM::ProtocolError, "record remains after deletion" unless missing?(resource, id, service: service)

    nil
  end

  def self.remove!(resource, id:, contract:, service:)
    raw = resource.delete(id)
    result = raw.is_a?(FivePM::Response) ? raw : FivePM::Response.new(raw, contract: contract)
    marker = result.status
    unless marker == true || (marker.is_a?(Integer) && marker.positive?)
      raise FivePM::ProtocolError, "record deletion did not succeed"
    end

    absent!(resource, id, service: service)
  end

  def self.cleanup!(resource, id:, contract:, service:)
    return if missing?(resource, id, service: service)

    remove!(resource, id: id, contract: contract, service: service)
  end
end
