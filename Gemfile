source "https://rubygems.org"
gemspec
# RuboCop uses parallel; the 2.x series requires Ruby 3.3.
gem "parallel", "~> 1.27.0"
gem "rake", "~> 13.0"
gem "rexml", "~> 3.4"
gem "rspec", "~> 3.13"
gem "rubocop", "~> 1.75"
gem "simplecov", "~> 1.2"

# Integration-test the separate adapter without adding MCP to the core runtime.
group :test do
  gemspec path: "mcp"
end
