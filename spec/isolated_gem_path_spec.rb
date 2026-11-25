# spec/isolated_gem_path_spec.rb
# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../bin/support/isolated_gem_path"

RSpec.describe IsolatedGemPath do
  def installed(base, name, version, extension: false)
    spec = Gem::Specification.new(name, version)
    path = File.join(base, "specifications", "#{spec.full_name}.gemspec")
    FileUtils.mkdir_p([File.dirname(path), File.join(base, "gems", spec.full_name)])
    File.write(path, spec.to_ruby)
    spec.loaded_from = path
    FileUtils.mkdir_p(spec.extension_dir) if extension
    spec
  end

  it "links bundle dependencies but never an installed copy of the packaged gems" do
    Dir.mktmpdir do |root|
      shared = File.join(root, "shared")
      specs = [installed(shared, "json", "2.9.1", extension: true),
               installed(shared, "5pm", "0.2.0"), installed(shared, "5pm-mcp", "0.2.0")]
      source = Gem::Specification.new("5pm", "0.2.1") # a path-sourced gem from the checkout
      source.loaded_from = File.join(root, "5pm.gemspec")
      isolated = described_class.build(specs + [source], File.join(root, "isolated"))

      expect(Dir.children(File.join(isolated, "specifications"))).to eq(["json-2.9.1.gemspec"])
      expect(Dir.children(File.join(isolated, "gems"))).to eq(["json-2.9.1"])
      extension = specs.first.extension_dir.delete_prefix(shared)
      expect(File.realpath(File.join(isolated, extension))).to eq(File.realpath(specs.first.extension_dir))
      expect(Gem::Specification.load(File.join(isolated, "specifications/json-2.9.1.gemspec")).name).to eq("json")
    end
  end
end
