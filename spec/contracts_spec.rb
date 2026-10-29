require "spec_helper"
require "rexml/document"

RSpec.describe "public demo WSDL operation inventory" do
  let(:namespace) { { "w" => "http://schemas.xmlsoap.org/wsdl/" } }

  it "matches every POST operation, request part and response part without inventing operations" do
    inventory = Dir[File.join(__dir__, "fixtures/wsdl/*.wsdl")].to_h do |path|
      document = REXML::Document.new(File.read(path))
      service = {}
      binding = REXML::XPath.first(document, "//w:binding[contains(@name,'HttpPost')]", namespace)
      supported = binding.get_elements("operation").map { |node| node.attributes["name"] }
      REXML::XPath.each(document, "//w:message", namespace) do |message|
        next unless message.attributes["name"].end_with?("HttpPostRequest")

        operation = message.attributes["name"].delete_suffix("HttpPostRequest")
        next unless supported.include?(operation)

        response = REXML::XPath.first(document, "//w:message[@name='#{operation}HttpPostResponse']", namespace)
        parts = ->(node) { node.elements.to_a.to_h { |part| [part.attributes["name"], part.attributes["type"]] } }
        service[operation] = { "parameters" => parts.call(message), "response" => parts.call(response) }
      end
      [File.basename(path, ".wsdl"), service]
    end
    expect(FivePM::OPERATIONS).to eq(inventory)
  end

  it "has POST bindings for every inventoried operation" do
    FivePM::OPERATIONS.each do |service, operations|
      document = REXML::Document.new(File.read(File.join(__dir__, "fixtures/wsdl/#{service}.wsdl")))
      binding = REXML::XPath.first(document, "//w:binding[contains(@name,'HttpPost')]", namespace)
      expect(binding).not_to be_nil
      expect(binding.get_elements("operation").map { |node| node.attributes["name"] }).to match_array(operations.keys)
    end
  end
end
