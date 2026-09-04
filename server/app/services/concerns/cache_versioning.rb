# frozen_string_literal: true

# CacheVersioning - structural replacement for Rails.cache.delete_matched
#
# config/environments/production.rb:50 defaults the production cache store to
# solid_cache, which implements no #delete_matched: the base
# ActiveSupport::Cache::Store#delete_matched (activesupport's cache.rb) raises
# NotImplementedError. That class descends from ScriptError, not
# StandardError, so a `rescue StandardError` guarding a delete_matched call
# does NOT catch it — the call propagates as an unhandled exception. See
# IMP-63a7d2f99c56 / IMP-95e4904258c8.
#
# Rather than deleting a pattern of keys (which requires the store to be able
# to enumerate/match keys), every cache key built through .key embeds a
# version segment for its scope; .bump! changes that segment so every
# previously-written key for the scope becomes unaddressable without needing
# to enumerate or delete it. This works on any ActiveSupport::Cache::Store
# that implements #read/#write/#increment — which MemoryStore and SolidCache
# both do (#delete_matched is what's missing, not #increment).
#
# Bumping does not free the old entries immediately; they fall out of the
# store on their own expiry. If a cache's volume matters, keep its
# expires_in short (as the existing TTL constants here already do).
#
# .bump! deliberately does not rescue anything: if a store cannot #increment
# either, that failure must be loud, not silently swallowed — a silently
# skipped invalidation is how the permission-cache defect this replaces
# stayed invisible (IMP-95e4904258c8, User#clear_permission_cache).
#
# Usage:
#   cache_key = CacheVersioning.key("mcp:registry:tools:#{account_id}", sort_by)
#   Rails.cache.fetch(cache_key) { ... }
#   ...
#   CacheVersioning.bump!("mcp:registry:tools:#{account_id}") # invalidates every key above
module CacheVersioning
  class << self
    # The scope's current version. Never written directly — only #bump!
    # advances it — so every call with the same `scope` and no intervening
    # #bump! returns the same value.
    # read_counter, not read: #bump! goes through the store's #increment, and
    # a store whose increment writes a RAW integer (RedisCacheStore's INCRBY)
    # cannot deserialize that payload on a plain #read — the coder answers nil
    # and the version would sit at 0 forever, silently retiring nothing.
    # ActiveSupport::Cache::Store#read_counter exists for this: it re-reads
    # with raw: true. Absent key answers nil, and nil.to_i is 0 — a scope that
    # has never been bumped is version 0, which is what .key expects.
    def version(scope, store: Rails.cache)
      store.read_counter(version_cache_key(scope)).to_i
    end

    # Advances `scope`'s version, retiring every cache key previously built
    # through .key for that scope.
    def bump!(scope, store: Rails.cache)
      store.increment(version_cache_key(scope), 1)
    end

    # Builds a cache key for `scope` (plus optional extra parts, e.g. a sort
    # field or a digest) that embeds the scope's current version.
    def key(scope, *parts, store: Rails.cache)
      ([ scope, "v#{version(scope, store: store)}" ] + parts.map(&:to_s)).join(":")
    end

    private

    def version_cache_key(scope)
      "#{scope}:cache_version"
    end
  end
end
