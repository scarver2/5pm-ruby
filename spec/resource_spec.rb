require "spec_helper"

RSpec.describe FivePM::Resource do
  let(:client) { double("client") }

  FivePM::Resource::OBJECT_PARAMETERS.each do |service, object|
    context service do
      subject(:resource) { described_class.new(client, service) }

      it "creates, reads, updates and deletes with verified wire names" do
        attributes = { "name" => "synthetic record", "futureField" => true }
        expect(client).to receive(:call).with(service, "add", **{ object => attributes }).and_return("created")
        expect(resource.create(attributes)).to eq("created")
        expect(client).to receive(:call).with(service, "getById", id: 7).and_return("read")
        expect(resource.get(7)).to eq("read")
        expect(client).to receive(:call).with(service, "update",
                                              **{ object => attributes.merge(id: 7) }).and_return("updated")
        expect(resource.update(attributes.merge(id: 7))).to eq("updated")
        expect(client).to receive(:call).with(service, "remove", id: 7).and_return(true)
        expect(resource.delete(7)).to be(true)
      end

      it "selects the supported list operation without assuming unsupported filters" do
        operation = FivePM::OPERATIONS.fetch(service).key?("getList") ? "getList" : "getAll"
        expect(client).to receive(:call).with(service, operation).and_return("list" => [])
        expect(resource.list).to eq("list" => [])
      end
    end
  end

  it "passes pagination, filters and explicit wire options without automatic requests" do
    resource = described_class.new(client, "tasks")
    expect(client).to receive(:call).with("tasks", "getList", filter: { projectId: 12 }, offset: 0,
                                                              count: 20, loadTeam: true).once.and_return({})
    resource.list(filter: { projectId: 12 }, offset: 0, count: 20, loadTeam: true)
  end

  it "requires an id for updates without discarding string or symbol keys" do
    resource = described_class.new(client, "tasks")
    [nil, [], {}, { name: "synthetic" }].each do |attributes|
      expect { resource.update(attributes) }.to raise_error(ArgumentError)
    end
    expect(client).to receive(:call).with("tasks", "update", "task" => { "id" => 7 }).and_return({})
    resource.update("id" => 7)
  end
end
