require "spec_helper"
require_relative "support/live_attachment_checks"

RSpec.describe LiveAttachmentChecks do
  let(:activity) { double("activity") }

  it "rejects a non-raising false deletion result" do
    expect(activity).to receive(:delete_file).with(7).and_return("data" => false)
    expect(activity).not_to receive(:files)
    expect { described_class.remove!(activity, task_id: 9, file_id: 7) }
      .to raise_error(FivePM::ProtocolError, "attachment deletion did not succeed")
  end

  it "rejects success responses when re-listing still contains the attachment" do
    expect(activity).to receive(:delete_file).with(7).and_return("data" => true)
    expect(activity).to receive(:files).with(filter: { taskId: 9 })
                                       .and_return("data" => { "items" => [{ "id" => "7" }] })
    expect { described_class.remove!(activity, task_id: 9, file_id: 7) }
      .to raise_error(FivePM::ProtocolError, "attachment remains after deletion")
  end

  it "verifies the target is absent while allowing unrelated attachments to remain" do
    expect(activity).to receive(:delete_file).with(7).and_return("data" => true)
    expect(activity).to receive(:files).with(filter: { taskId: 9 })
                                       .and_return("data" => { "items" => [{ "id" => "8" }] })
    expect { described_class.remove!(activity, task_id: 9, file_id: 7) }.not_to raise_error
  end
end
