# frozen_string_literal: true

require "json"

# Helper for Gemfile to dynamically discover extension gems.
# Scans extensions/*/extension.json for gems with components.server: true.
# Skips slugs marked disabled in config/extensions_state.json so a disabled
# extension never becomes a path gem (its Engine is never loaded).
def discover_extension_gems
  discover_extension_gems_by_visibility[:public] +
    discover_extension_gems_by_visibility[:private]
end

# Partition discovered extensions by visibility — "public" = listed in
# .gitmodules (so present in every clone of the public repo), "private"
# = present on disk but NOT in .gitmodules (added locally by maintainers
# with access to the private upstream).
#
# The Gemfile uses this partition to put private extensions inside an
# `optional: true` bundler group. CI's default `bundle install` skips
# optional groups, so missing-on-disk private extensions don't produce
# a Gemfile.lock that mismatches what CI declares. Maintainers who
# want private extensions installed run `bundle install --with
# private_extensions` (or set BUNDLE_WITH=private_extensions in env).
#
# Returns a hash with :public and :private keys, each an array of
# [slug, relative-path] pairs in the same shape as discover_extension_gems.
#
# ENV[POWERNODE_HIDE_PRIVATE_EXTENSIONS]=1 forces the :private bucket
# empty even when extensions are present on disk — needed when
# regenerating the committed Gemfile.lock from a maintainer's machine
# (which has business + trading on disk). Without this knob, bundler's
# resolve would write `powernode_business!` etc. into Gemfile.lock and
# CI's frozen-mode install would fail. Use:
#   POWERNODE_HIDE_PRIVATE_EXTENSIONS=1 bundle install
# scripts/regen-public-lockfile.sh wraps this for convenience.
def discover_extension_gems_by_visibility
  hide_private = ENV["POWERNODE_HIDE_PRIVATE_EXTENSIONS"] == "1"
  dir = File.join(__dir__, "extensions")
  return { public: [], private: [] } unless Dir.exist?(dir)

  disabled = disabled_extension_slugs
  public_slugs = public_extension_slugs

  result = { public: [], private: [] }
  Dir.children(dir).sort.each do |slug|
    next if disabled.include?(slug)

    manifest = File.join(dir, slug, "extension.json")
    next unless File.exist?(manifest)

    parsed = JSON.parse(File.read(manifest))
    next unless parsed.dig("components", "server")

    server_path = File.join(dir, slug, "server")
    next unless Dir.exist?(server_path)

    is_public = public_slugs.include?(slug)
    next if !is_public && hide_private

    bucket = is_public ? :public : :private
    result[bucket] << [slug, "../extensions/#{slug}/server"]
  end
  result
end

# Set of extension slugs declared in .gitmodules — the canonical
# definition of "public extension." Everything in extensions/ that is
# not in this set is treated as private. Returns an empty Set when
# .gitmodules is absent (e.g., a stripped checkout); in that case every
# discovered extension falls through to :private and the Gemfile's
# optional-group bundler config skips them all by default.
def public_extension_slugs
  gitmodules = File.join(__dir__, ".gitmodules")
  return [] unless File.exist?(gitmodules)
  File.read(gitmodules).scan(%r{^\s*path\s*=\s*extensions/([^\s]+)$}).flatten
rescue IOError, SystemCallError
  []
end

def disabled_extension_slugs
  state_file = File.join(__dir__, "config", "extensions_state.json")
  return [] unless File.exist?(state_file)

  state = JSON.parse(File.read(state_file))
  Array(state["disabled"]).map(&:to_s)
rescue JSON::ParserError, IOError, SystemCallError
  []
end
