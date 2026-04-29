# frozen_string_literal: true

require "json"

# Helper for Gemfile to dynamically discover extension gems.
# Scans extensions/*/extension.json for gems with components.server: true.
# Skips slugs marked disabled in config/extensions_state.json so a disabled
# extension never becomes a path gem (its Engine is never loaded).
def discover_extension_gems
  dir = File.join(__dir__, "extensions")
  return [] unless Dir.exist?(dir)

  disabled = disabled_extension_slugs

  Dir.children(dir).sort.filter_map do |slug|
    next if disabled.include?(slug)

    manifest = File.join(dir, slug, "extension.json")
    next unless File.exist?(manifest)

    parsed = JSON.parse(File.read(manifest))
    next unless parsed.dig("components", "server")

    server_path = File.join(dir, slug, "server")
    next unless Dir.exist?(server_path)

    [slug, "../extensions/#{slug}/server"]
  end
end

def disabled_extension_slugs
  state_file = File.join(__dir__, "config", "extensions_state.json")
  return [] unless File.exist?(state_file)

  state = JSON.parse(File.read(state_file))
  Array(state["disabled"]).map(&:to_s)
rescue JSON::ParserError, IOError, SystemCallError
  []
end
