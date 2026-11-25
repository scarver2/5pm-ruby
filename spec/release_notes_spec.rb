# spec/release_notes_spec.rb
# frozen_string_literal: true

require "spec_helper"
require_relative "../bin/support/release_notes"

RSpec.describe ReleaseNotes do
  let(:changelog) do
    "# Changelog\n\n## 0.2.2 — 2026-12-01\n\n- Fix the thing.\n\n## 0.2.1 — 2026-11-25\n\n- Older.\n"
  end

  it "builds notes from only the version's changelog entries" do
    notes = described_class.build(changelog: changelog, version: "0.2.2", commit: "a" * 40, previous: "v0.2.1",
                                  ruby: "Ruby 3.2 or newer", adapter_dependencies: ["5pm ~> 0.2.0"],
                                  run_url: "https://example.invalid/run/1")
    expect(notes).to include("## Changes\n\n- Fix the thing.\n\n## Published gems")
    expect(notes).not_to include("Older.")
    expect(notes).to include("https://rubygems.org/gems/5pm-mcp/versions/0.2.2", "depends on `5pm ~> 0.2.0`",
                             "Both gems require Ruby 3.2 or newer", "[Release workflow run](https://example.invalid/run/1)",
                             "/commit/#{'a' * 40}", "/compare/v0.2.1...v0.2.2", "Made in Texas")
  end

  it "refuses a missing or empty version section" do
    expect { described_class.section(changelog, "0.3.0") }.to raise_error(described_class::Error, /no dated 0.3.0/)
    expect { described_class.section("## 0.3.0 — 2026-12-01\n\n## 0.2.2 — 2026-11-30\n- x\n", "0.3.0") }
      .to raise_error(described_class::Error, /empty/)
  end

  it "compares against the newest earlier stable tag" do
    tags = %w[v0.1.0 v0.2.0 v0.10.0 v0.2.1 v0.2.1-rc1 latest]
    expect(described_class.previous_tag(tags, "0.3.0")).to eq("v0.2.1")
    expect(described_class.previous_tag(tags, "0.11.0")).to eq("v0.10.0")
    expect(described_class.previous_tag(tags, "0.1.0")).to be_nil
  end

  it "reads the Ruby minimum and adapter dependencies from the gemspecs" do
    root = File.expand_path("..", __dir__)
    expect(described_class.ruby_requirement(File.read(File.join(root, "5pm.gemspec")))).to eq("Ruby 3.2 or newer")
    expect(described_class.adapter_dependencies(File.read(File.join(root, "mcp/5pm-mcp.gemspec"))))
      .to match([/\A5pm ~> \d+\.\d+\.0\z/, /\Amcp >= [\d.]+, < [\d.]+\z/])
  end
end
