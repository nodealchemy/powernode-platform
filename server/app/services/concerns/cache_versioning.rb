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
# that implements #read/#write — the two operations every store has.
#
# Bumping does not free the old entries immediately; they fall out of the
# store on their own expiry. If a cache's volume matters, keep its
# expires_in short (as the existing TTL constants here already do).
#
# .bump! DOES NOT RESCUE, BUT THE STORE MIGHT — and that distinction matters
# enough to state, because an earlier version of this comment claimed a write
# failure would be loud and that was false. solid_cache wraps write_entry in
# `failsafe(:write_entry, returning: nil)`, which swallows every transient
# ActiveRecord error (ConnectionNotEstablished, AdapterTimeout, Deadlocked,
# LockWaitTimeout, QueryCanceled, StatementTimeout) and answers nil
# (store/entries.rb:51, store/failsafe.rb:6-36); RedisCacheStore does the same
# via `failsafe :write_entry, returning: nil`. So a DB blip or a Redis
# reconnect during an invalidation silently persists nothing, version keeps
# answering the PREVIOUS token, and every key built before the bump stays
# addressable for the rest of its TTL — a pre-rotation secret served after an
# explicit invalidation, which is exactly the IMP-95e4904258c8 class.
#
# The concern cannot un-swallow the store's rescue, so it does the next thing:
# it INSPECTS the write's return value and logs an error when the store
# reports failure, and returns nil rather than a token that was never
# persisted. Callers that care can check the return; the log line is what
# makes a silently skipped invalidation visible at all.
#
# ── WHY A TOKEN AND NOT A COUNTER (IMP-a95f7b6b3e01) ──────────────────────
#
# The version was originally a monotonic counter. A counter is only unique
# while its own cache entry survives, and the version entry is EVICTABLE like
# any other. Once it is swept, a counter restarts: version reads absent, the
# next .bump! writes 1, and every key string previously issued at v1 is
# addressable again — anything still cached under one is served after an
# explicit invalidation.
#
# WHAT MAKES THAT REACHABLE under solid_cache 1.0.10, stated per-clause because
# the composite is easy to overstate:
#   - The version entry's id never moves. Entry.write_multi upserts
#     `update_only: [:key, :value, :byte_size]` (entry.rb:29), so an updated
#     row keeps its original id AND created_at.
#   - Sweep candidates are the oldest window by id, then a RANDOM SAMPLE of it:
#     `order(:id).limit(count * 3)` then `candidate_ids.sample(count)`
#     (entry/expiration.rb:37-49). Not oldest-first.
#   - config/cache.yml sets no max_age, so it keeps the 2.weeks default
#     (store/expiry.rb:18) and expiration.rb:28
#     (`return [] unless cache_full || max_age`) runs a sweep on every expiry
#     pass. The AGE branch still only deletes rows older than max_age, so it
#     cannot touch a version entry until it is two weeks old — routine eviction
#     of a live version entry comes from the CACHE_FULL branch
#     (max_size: 256 MB), which ignores created_at entirely.
#
# NOT A LIVE DEFECT ON THIS DEPLOYMENT, and the comment should not read as one:
# the hub pins CACHE_STORE=memory_store, dev uses redis_cache_store, test uses
# memory_store. This is a PREREQUISITE for adopting solid_cache, which is why
# it lands before that decision rather than with it. The failure it forecloses
# is concrete: Security::VaultClient bumps "vault:<path>" on write/delete with
# a 5-minute read TTL (vault_client.rb:12), so a resurrected key there means a
# PRE-ROTATION secret served after a rotation.
#
# A non-repeating token cannot do that: no value .bump! produces has ever been
# produced before, so no retired key becomes addressable again. Losing the
# entry degrades to a cache MISS (safe) instead of a stale HIT (not).
#
# NO SHARED "NEVER BUMPED" NAMESPACE EITHER. An earlier draft answered a
# constant "0" when the version entry was absent, and justified the residual
# risk with "v0 entries are older than the version entry, and the sweep takes
# oldest ids first, so they go first". That reasoning is WRONG:
# expiry_candidate_ids takes `order(:id).limit(count * 3)` and then
# `candidate_ids.sample(count)` (entry/expiration.rb:37-49) — a random sample
# of the oldest window, not oldest-first — and in the cache_full branch
# created_at is not consulted at all. The version entry and its coeval data
# entries enter the same window and the sample decides which dies first.
#
# Worse, a constant sentinel is not a race window but a PERSISTENT shared
# namespace: every absence period reuses "v0", so an entry cached during one
# absence is re-addressable during the next, across an intervening bump.
#
# So absence SEEDS instead: #version writes a fresh token when it reads none.
# The seed costs one write per scope per store lifetime (the entry exists
# after that), and two readers racing to seed simply write different tokens —
# last writer wins and the losers get cache MISSES, never a stale hit.
#
# ── SCOPE OF AN INVALIDATION: PER-STORE, NOT PER-FLEET ────────────────────
#
# A bump reaches exactly as far as the store it is written to. On a hub that
# pins CACHE_STORE=memory_store (extensions/system/modules/
# powernode-hub-backend/manifest.yaml), each puma worker holds its OWN
# ActiveSupport::Cache::MemoryStore, so a bump in one worker retires nothing in
# the others or in hub-worker. That is a property of the configured store, not
# of this concern, and it predates the delete_matched migration — MemoryStore's
# #delete_matched was equally per-process. Do NOT read ".bump! invalidates
# every key above" as fleet-wide: it is true within one store.
#
# Making it cross-process means pointing CACHE_STORE at a shared backend, which
# is a deploy decision with its own boot-reachability risk, not a change to
# this file. spec/services/concerns/cache_versioning_spec.rb pins BOTH halves
# (a bump not crossing two independent stores, and crossing one shared store)
# so this paragraph cannot quietly drift from the behaviour.
#
# Usage:
#   cache_key = CacheVersioning.key("mcp:registry:tools:#{account_id}", sort_by)
#   Rails.cache.fetch(cache_key) { ... }
#   ...
#   CacheVersioning.bump!("mcp:registry:tools:#{account_id}") # invalidates every key above
module CacheVersioning
  class << self
    # The scope's current version token. Stable for a given scope until #bump!
    # replaces it, so every call with no intervening #bump! returns the same
    # value. When no token is stored — never bumped, or the entry was evicted —
    # a fresh one is SEEDED rather than falling back to a shared constant; see
    # the header for why a constant sentinel is a stale-hit hazard.
    def version(scope, store: Rails.cache)
      stored = store.read(version_cache_key(scope))
      return stored.to_s if stored.present?

      write_token(scope, store: store, on_failure: :ignore)
    end

    # Advances `scope`'s version, retiring every cache key previously built
    # through .key for that scope. Returns the new token, or nil if the store
    # reported that it did not persist it (see the header: solid_cache and
    # RedisCacheStore both swallow transient failures and answer nil).
    def bump!(scope, store: Rails.cache)
      write_token(scope, store: store, on_failure: :log)
    end

    # Builds a cache key for `scope` (plus optional extra parts, e.g. a sort
    # field or a digest) that embeds the scope's current version.
    def key(scope, *parts, store: Rails.cache)
      ([ scope, "v#{version(scope, store: store)}" ] + parts.map(&:to_s)).join(":")
    end

    private

    # Writes a fresh token for `scope`. A store that reports failure (nil or
    # false) gets an error log on the #bump! path — where a skipped write means
    # a skipped INVALIDATION and stale reads — and silence on the #version
    # seeding path, where a failed write only costs a re-seed and a cache miss
    # on the next read.
    def write_token(scope, store:, on_failure:)
      token = new_token
      written = store.write(version_cache_key(scope), token)
      return token unless written.nil? || written == false

      if on_failure == :log
        Rails.logger.error(
          "[CacheVersioning] store #{store.class} did not persist the version bump for " \
          "#{scope.inspect} (write returned #{written.inspect}) — keys built before this " \
          "bump remain addressable until their own TTL expires"
        )
        return nil
      end

      token
    end

    # Monotonic-ish wall clock at nanosecond resolution, plus random bytes so
    # two processes bumping inside the same nanosecond — or a clock stepped
    # backwards — still cannot collide.
    def new_token
      "#{Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)}#{SecureRandom.hex(6)}"
    end

    def version_cache_key(scope)
      "#{scope}:cache_version"
    end
  end
end
