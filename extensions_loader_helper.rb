# frozen_string_literal: true

require "json"

# Helper for Gemfile to dynamically discover extension gems.
# Scans extensions/*/extension.json for gems with components.server: true.
# Skips slugs marked disabled in config/extensions_state.json so a disabled
# extension never becomes a path gem (its Engine is never loaded).
#
# Every entry point takes an optional `base_dir` (defaulting to this file's
# own directory — the repo root) purely for testability: production callers
# (the Gemfile) pass nothing and read the real tree, while specs point the
# whole discovery at a fixture root. The default preserves the original
# behavior exactly, so no call site changes.
def discover_extension_gems(base_dir = __dir__)
  discover_extension_gems_by_visibility(base_dir)[:public] +
    discover_extension_gems_by_visibility(base_dir)[:private]
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
# maintainer's machine (which has private extensions on disk) produces a
# public-only Gemfile.lock automatically — no manual regen step, and the
# committed lock never declares `powernode_business!` etc. that CI's frozen
# install can't resolve. Opt IN to declaring + loading private extensions
# for private-mode dev via the separate, gitignored bundle:
#   BUNDLE_GEMFILE=Gemfile.private bundle install   # writes Gemfile.private.lock
# (server/Gemfile.private just flips this flag and re-uses the base Gemfile.)
# The committed lock is plain `bundle lock` (no env / no BUNDLE_GEMFILE);
# scripts/regen-public-lockfile.sh remains as a convenience wrapper.
def discover_extension_gems_by_visibility(base_dir = __dir__)
  include_private = ENV["POWERNODE_INCLUDE_PRIVATE_EXTENSIONS"] == "1"
  # Deployed control planes (the hub-backend rails service sets
  # POWERNODE_DEPLOYED=1) load EVERY extension present on disk, regardless of
  # public/private: on a node, presence-on-disk IS the composition decision — a
  # NodeModule put it there. dev/CI leave the flag unset, so discovery stays
  # gated on .gitmodules (public) or the POWERNODE_INCLUDE_PRIVATE_EXTENSIONS
  # opt-in, preserving the public-only committed-lock invariant. Distinct from
  # the private opt-in: DEPLOYED loads public AND private on-disk extensions
  # (they only reach the node's disk by being composed), but only ever at
  # runtime on a node — never during the committed `bundle lock`.
  deployed = ENV["POWERNODE_DEPLOYED"] == "1"
  dir = File.join(base_dir, "extensions")
  return { public: [], private: [] } unless Dir.exist?(dir)

  disabled = disabled_extension_slugs(base_dir)
  public_slugs = public_extension_slugs(base_dir)

  result = { public: [], private: [] }
  extension_candidate_dirs(dir).each do |slug, rel_path, private_by_location|
    next if disabled.include?(slug)

    manifest = File.join(base_dir, rel_path, "extension.json")
    next unless File.exist?(manifest)

    parsed = JSON.parse(File.read(manifest))
    next unless parsed.dig("components", "server")

    server_path = File.join(base_dir, rel_path, "server")
    next unless Dir.exist?(server_path)

    is_public = !private_by_location && public_slugs.include?(slug)
    next if !deployed && !is_public && !include_private

    bucket = is_public ? :public : :private
    result[bucket] << [slug, "../#{rel_path}/server"]
  end
  result
end

# Yields [slug, path-relative-to-base_dir, private_by_location] for every
# extension directory. Extensions live flat under extensions/<slug>; private/
# custom ones under extensions/private/<slug> (the whole extensions/private/
# tree is gitignored). "private" is a grouping directory, never an extension
# slug — anything under it is private by location regardless of .gitmodules.
def extension_candidate_dirs(extensions_dir)
  candidates = []
  Dir.children(extensions_dir).sort.each do |name|
    next if name == "private"
    candidates << [name, "extensions/#{name}", false]
  end
  private_dir = File.join(extensions_dir, "private")
  if Dir.exist?(private_dir)
    Dir.children(private_dir).sort.each do |name|
      candidates << [name, "extensions/private/#{name}", true]
    end
  end
  candidates
end

# Set of extension slugs declared in .gitmodules — the canonical
# definition of "public extension." Everything in extensions/ that is
# not in this set is treated as private. Returns an empty Set when
# .gitmodules is absent (e.g., a stripped checkout); in that case every
# discovered extension falls through to :private and the Gemfile's
# optional-group bundler config skips them all by default.
def public_extension_slugs(base_dir = __dir__)
  gitmodules = File.join(base_dir, ".gitmodules")
  return [] unless File.exist?(gitmodules)
  File.read(gitmodules).scan(%r{^\s*path\s*=\s*extensions/([^\s]+)$}).flatten
rescue IOError, SystemCallError
  []
end

def disabled_extension_slugs(base_dir = __dir__)
  state_file = File.join(base_dir, "config", "extensions_state.json")
  return [] unless File.exist?(state_file)

  state = JSON.parse(File.read(state_file))
  Array(state["disabled"]).map(&:to_s)
rescue JSON::ParserError, IOError, SystemCallError
  []
end
