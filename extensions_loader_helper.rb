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
# discover_extension_gems (used by the Gemfile) returns :public + :private,
# but :private is empty unless explicitly opted in (see below), so by default
# only public extensions become path gems. CI + public clones don't have the
# private submodules on disk anyway, so they only ever see public extensions.
#
# Returns a hash with :public and :private keys, each an array of
# [slug, relative-path] pairs in the same shape as discover_extension_gems.
#
# Private extensions are EXCLUDED from the :private bucket BY DEFAULT, so a
# maintainer's machine (which has business + trading on disk) produces a
# public-only Gemfile.lock automatically — no manual regen step, and the
# committed lock never declares `powernode_business!` etc. that CI's frozen
# install can't resolve. Opt IN to declaring + loading private extensions
# for full-mode dev via the separate, gitignored bundle:
#   BUNDLE_GEMFILE=Gemfile.full bundle install   # writes Gemfile.full.lock
# (server/Gemfile.full just flips this flag and re-uses the base Gemfile.)
# The committed lock is plain `bundle lock` (no env / no BUNDLE_GEMFILE);
# scripts/regen-public-lockfile.sh remains as a convenience wrapper.
def discover_extension_gems_by_visibility
  include_private = ENV["POWERNODE_INCLUDE_PRIVATE_EXTENSIONS"] == "1"
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
    next if !is_public && !include_private

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
