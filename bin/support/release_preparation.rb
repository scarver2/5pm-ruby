# bin/support/release_preparation.rb
# frozen_string_literal: true

require "date"
require "rubygems"

# Pure text transformations behind bin/release-prepare. Each method returns the
# updated text or raises ReleasePreparation::Error, so nothing is written unless
# every file can be prepared.
module ReleasePreparation
  class Error < StandardError; end

  STABLE = /\A(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\z/
  DATE = /\A\d{4}-\d{2}-\d{2}\z/
  UNRELEASED = /^## Unreleased[ \t]*\n/

  module_function

  def check_version!(current, version)
    raise Error, "expected a stable version such as 1.2.3" unless STABLE.match?(version)
    raise Error, "#{version} must be greater than the current #{current}" unless
      Gem::Version.new(version) > Gem::Version.new(current)
  end

  # The adapter accepts any core release in the same minor series.
  def core_requirement(version)
    major, minor, = version.split(".")
    "~> #{major}.#{minor}.0"
  end

  def version_source(text, current, version)
    replace_exactly(text, /^(\s*VERSION = )"#{Regexp.escape(current)}"/, "version constant") do |prefix|
      %(#{prefix}"#{version}")
    end
  end

  # Moves the Unreleased entries under a dated heading for the new version.
  def changelog(text, version, date)
    real = DATE.match?(date) && Date.valid_date?(*date.split("-").map(&:to_i))
    raise Error, "expected a real YYYY-MM-DD release date" unless real
    raise Error, "CHANGELOG.md already has a #{version} section" if text.match?(/^## #{Regexp.escape(version)}\b/)

    heading = text.match(UNRELEASED)
    raise Error, "CHANGELOG.md has no ## Unreleased section to release" unless heading

    rest = text[heading.end(0)..]
    following = rest.index(/^## /) || rest.length
    entries = rest[0...following].strip
    raise Error, "the ## Unreleased section has no entries" unless entries.match?(/^- /)

    "#{text[0...heading.begin(0)]}## #{version} — #{date}\n\n#{entries}\n\n#{rest[following..]}"
  end

  def adapter_gemspec(text, version)
    replace_exactly(text, /^(\s*spec\.add_dependency "5pm", )"~> \d+\.\d+\.\d+"/, "5pm dependency") do |prefix|
      %(#{prefix}"#{core_requirement(version)}")
    end
  end

  # Updates the two path gems and the adapter's core requirement in a lockfile.
  def lockfile(text, current, version)
    path_gem = /^(\s+)(5pm|5pm-mcp) \(#{Regexp.escape(current)}\)$/
    %w[5pm 5pm-mcp].each do |name|
      raise Error, "lockfile does not list #{name} #{current}" unless
        text.match?(/^\s+#{name} \(#{Regexp.escape(current)}\)$/)
    end
    text.gsub(path_gem, "\\1\\2 (#{version})")
        .gsub(/^(\s+5pm \()~> \d+\.\d+\.\d+\)$/, "\\1#{core_requirement(version)})")
  end

  # Updates install commands, Bundler constraints and version links. Historical
  # mentions such as "Available since 0.2.0" are not install instructions and stay.
  def install_docs(text, current, version)
    old = Regexp.escape(current)
    patterns = [/(--version )#{old}\b()/, /("~> )#{old}(")/, %r{(/versions/)#{old}\b()},
                %r{(/(?:tree|releases/tag)/v)#{old}\b()}, /(`v)#{old}(`)/, /(\*\*)#{old}(\*\*)/,
                /(\[)#{old}( is published)/]
    updated = patterns.reduce(text) { |result, pattern| result.gsub(pattern, "\\1#{version}\\2") }
    raise Error, "no install instructions for #{current} were found" if updated == text

    updated
  end

  def replace_exactly(text, pattern, label)
    matches = text.scan(pattern).length
    raise Error, "expected exactly one #{label}, found #{matches}" unless matches == 1

    text.sub(pattern) { yield ::Regexp.last_match(1) }
  end
end
