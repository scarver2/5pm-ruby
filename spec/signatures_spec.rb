require "spec_helper"
require "rbs"
require "five_pm/mcp"

RSpec.describe "published RBS API coverage" do
  it "declares every public SDK, model and adapter instance method" do
    loader = RBS::EnvironmentLoader.new
    %w[sig mcp/sig].each { |path| loader.add(path: Pathname(File.expand_path("../#{path}", __dir__))) }
    environment = RBS::Environment.from_loader(loader).resolve_type_names
    builder = RBS::DefinitionBuilder.new(env: environment)
    models = FivePM::Models.constants.filter_map do |name|
      value = FivePM::Models.const_get(name)
      value if value.is_a?(Class)
    end
    classes = [FivePM::Client, FivePM::Service, FivePM::Resource, FivePM::Authentication,
               FivePM::Users, FivePM::Activity, FivePM::Download, FivePM::Transport,
               FivePM::RetryPolicy, FivePM::Response, FivePM::SchemaError, FivePM::APIError,
               FivePM::HTTPError, FivePM::RateLimitError, FivePM::MCPAdapter::Server, *models]
    classes.each do |type|
      name = environment.class_decls.keys.find { |key| key.to_s == "::#{type.name}" }
      expect(name).not_to be_nil, "missing signature for #{type.name}"
      declared = builder.build_instance(name).methods.keys
      public_api = type.public_instance_methods(false) - %i[method_missing respond_to_missing?]
      expect(public_api - declared).to eq([]), "missing public methods for #{type.name}"
    end
  end
end
