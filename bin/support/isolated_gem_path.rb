# bin/support/isolated_gem_path.rb
# frozen_string_literal: true

require "fileutils"
require "pathname"

# Builds a gem directory holding links to the bundle's installed dependencies only.
# Pointing GEM_PATH at a whole shared gem directory would also expose any published
# copy of the gems being verified, and RubyGems could load that copy instead.
module IsolatedGemPath
  PACKAGED = %w[5pm 5pm-mcp].freeze

  module_function

  def build(specs, directory, exclude: PACKAGED)
    FileUtils.mkdir_p(File.join(directory, "specifications"))
    specs.each do |spec|
      next if exclude.include?(spec.name) || spec.default_gem?
      next unless installed?(spec)

      link(spec.loaded_from, File.join(directory, "specifications", File.basename(spec.loaded_from)))
      link(spec.full_gem_path, File.join(directory, "gems", spec.full_name))
      extensions = spec.extension_dir
      next unless File.directory?(extensions)

      relative = Pathname(extensions).relative_path_from(Pathname(spec.base_dir))
      link(extensions, File.join(directory, relative))
    end
    directory
  end

  # Only gems installed from a gem server have a specification file in a gem directory.
  def installed?(spec)
    spec.loaded_from && File.basename(File.dirname(spec.loaded_from)) == "specifications" &&
      File.directory?(spec.full_gem_path)
  end

  def link(source, destination)
    FileUtils.mkdir_p(File.dirname(destination))
    File.symlink(source, destination)
  end
end
