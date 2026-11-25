# spec/mcp_minimum_gemfile_spec.rb
# frozen_string_literal: true

require "spec_helper"

RSpec.describe "minimum mcp Gemfile" do
  def statements(path)
    File.readlines(File.expand_path(path, File.expand_path("..", __dir__)))
        .map(&:strip).reject { |line| line.empty? || line.start_with?("#") }
  end

  it "mirrors the main Gemfile except for its paths and the mcp pin" do
    main = statements("Gemfile")
    minimum = statements("gemfiles/mcp_minimum.gemfile")
    normalized = minimum.reject { |line| line.start_with?('gem "mcp"') }
                        .map { |line| line.sub('gemspec path: ".."', "gemspec").sub('path: "../mcp"', 'path: "mcp"') }
    expect(normalized).to eq(main)
  end

  it "pins the lower bound that 5pm-mcp declares" do
    gemspec = File.read(File.expand_path("../mcp/5pm-mcp.gemspec", __dir__))
    lower = gemspec[/add_dependency "mcp", ">= ([\d.]+)"/, 1]
    expect(statements("gemfiles/mcp_minimum.gemfile")).to include(%(gem "mcp", "#{lower}"))
  end
end
