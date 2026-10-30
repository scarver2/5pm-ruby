require "five_pm"

module LiveAttachmentChecks
  def self.remove!(activity, task_id:, file_id:)
    deletion = FivePM::Response.new(activity.delete_file(file_id),
                                    contract: FivePM::OPERATIONS.dig("activity", "removeFile"))
    raise FivePM::ProtocolError, "attachment deletion did not succeed" unless deletion.status == true

    remaining = FivePM::Response.new(activity.files(filter: { taskId: task_id }),
                                     contract: FivePM::OPERATIONS.dig("activity", "getFilesList"))
    return unless remaining.list.items.any? { |file| file.id == file_id }

    raise FivePM::ProtocolError, "attachment remains after deletion"
  end
end
