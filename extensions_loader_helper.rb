# frozen_string_literal: true

require "json"

# Helper for Gemfile to dynamically discover extension gems.
# Scans extensions/*/extension.json for gems with components.server: true.
def discover_extension_gems
  dir = File.join(__dir__, "extensions")
  return [] unless Dir.exist?(dir)

  Dir.children(dir).sort.filter_map do |slug|
    manifest = File.join(dir, slug, "extension.json")
    next unless File.exist?(manifest)

    parsed = JSON.parse(File.read(manifest))
    next unless parsed.dig("components", "server")

    server_path = File.join(dir, slug, "server")
    next unless Dir.exist?(server_path)

    [slug, "../extensions/#{slug}/server"]
  end
end
