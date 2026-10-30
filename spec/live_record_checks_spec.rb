require "spec_helper"
require_relative "support/live_record_checks"

RSpec.describe LiveRecordChecks do
  let(:resource) { double("resource") }
  let(:contract) { FivePM::OPERATIONS.dig("users", "remove") }

  it "rejects false, null and zero deletion responses before verifying absence" do
    [false, nil, 0].each do |marker|
      expect(resource).to receive(:delete).with(7).and_return("data" => marker)
      expect(resource).not_to receive(:get)
      expect { described_class.remove!(resource, id: 7, contract: contract, service: :users) }
        .to raise_error(FivePM::ProtocolError, "record deletion did not succeed")
    end
  end

  it "propagates failed absence checks so callers retain their cleanup entries" do
    [FivePM::TransportError.new, FivePM::ProtocolError.new].each do |error|
      expect(resource).to receive(:delete).with(7).and_return("data" => true)
      expect(resource).to receive(:get).with(7).and_raise(error)
      expect do
        described_class.remove!(resource, id: 7, contract: contract, service: :users)
      end.to raise_error(error.class)
    end
  end

  it "rejects successful deletion responses if the record remains" do
    expect(resource).to receive(:delete).with(7).and_return("data" => true)
    expect(resource).to receive(:get).with(7).and_return("data" => { "id" => 7 })
    expect { described_class.remove!(resource, id: 7, contract: contract, service: :users) }
      .to raise_error(FivePM::ProtocolError, "record remains after deletion")
  end

  it "confirms deletion only after a missing-record response" do
    expect(resource).to receive(:delete).with(7).ordered.and_return("data" => true)
    expect(resource).to receive(:get).with(7).ordered.and_raise(FivePM::APIError, 0)
    expect(resource).to receive(:list).ordered.and_return("data" => { "items" => [] })
    expect(described_class.remove!(resource, id: 7, contract: contract, service: :users)).to be_nil
  end

  it "does not replay a deletion that already succeeded when cleanup checks absence" do
    expect(resource).to receive(:get).with(7).and_raise(FivePM::APIError, 0)
    expect(resource).to receive(:list).and_return("data" => { "items" => [] })
    expect(resource).not_to receive(:delete)
    expect(described_class.cleanup!(resource, id: 7, contract: contract, service: :users)).to be_nil
  end

  it "does not mistake generic user lookup errors for absence when the list still contains the user" do
    expect(resource).to receive(:get).with(7).and_raise(FivePM::APIError, 0)
    expect(resource).to receive(:list).and_return("data" => { "items" => [{ "id" => "7" }] })
    expect { described_class.absent!(resource, 7, service: :users) }
      .to raise_error(FivePM::ProtocolError, "record remains after deletion")
  end

  it "propagates unexpected API errors from services with specific missing-record codes" do
    expect(resource).to receive(:get).with(7).and_raise(FivePM::APIError, 431)
    expect { described_class.absent!(resource, 7, service: :projects) }.to raise_error(FivePM::APIError)
  end
end
