# frozen_string_literal: true

module Ai
  module DataSources
    # Redis-backed response cache for external data-source fetches.
    #
    # Mirrors the access/metrics shape of Ai::Learning::PromptCacheService
    # (Redis DB 0 via Powernode::Redis.client, SHA256 keys, setex TTL,
    # hits/misses metrics) and adds two cache-stampede protections:
    #
    #   1. SINGLEFLIGHT — on a miss only one caller recomputes. The recompute
    #      lock is a per-key Redis SETNX (SET NX PX). Other concurrent callers
    #      briefly poll for the freshly written value, and serve the previous
    #      (stale) value if one is still around, before falling back to their
    #      own recompute.
    #
    #   2. Probabilistic early refresh (XFetch / "optimal cache stampede
    #      prevention", Vattani/Chierichetti/Lowenstein 2015). Each entry stores
    #      the recompute cost (delta) and its hard-expiry epoch. A reader rolls
    #      gamma = delta * BETA * -ln(random) and treats the value as expired
    #      when now + gamma >= expiry, so exactly one early reader regenerates
    #      the value just before it would have expired — under the recompute
    #      lock, so the regeneration itself is still single-flighted.
    class ResponseCacheService
      # Fallback TTL when an endpoint declares no cache_ttl_seconds.
      DEFAULT_TTL = 5.minutes

      # Redis key namespaces (Redis DB 0, shared client).
      REDIS_NAMESPACE  = "data_source_cache"
      METRICS_NAMESPACE = "data_source_cache:metrics"
      LOCK_NAMESPACE   = "data_source_cache:lock"

      # XFetch tuning. BETA > 1 makes early refresh more aggressive; 1.0 is the
      # canonical default. The roll uses the recorded recompute cost so that
      # expensive entries refresh earlier (proportionally to their cost).
      XFETCH_BETA = 1.0

      # Singleflight lock behaviour.
      LOCK_TTL_SECONDS    = 30      # safety cap so a crashed holder can't wedge the key
      LOCK_WAIT_TIMEOUT_S = 5.0     # max time a non-holder waits for the holder's value
      LOCK_POLL_INTERVAL_S = 0.05   # poll cadence while waiting for the holder

      # Metrics counters live for a rolling week, like the prompt cache.
      METRICS_TTL_SECONDS = 7.days.to_i

      class << self
        # Single-flighted fetch-or-compute.
        #
        # On a hit (and not an XFetch early-refresh roll) returns the cached
        # payload. On a miss / early-refresh, the block is invoked under a
        # per-key recompute lock; its return value (the fetch payload) is cached
        # and returned. Concurrent callers that lose the lock race wait briefly
        # for the holder's value and serve the last known value if present.
        #
        # Returns the (possibly cached) payload, or the freshly computed payload.
        def fetch(data_source:, endpoint:, params: {}, &block)
          raise ArgumentError, "block required" unless block_given?

          # Per-source kill flag: when the cache is disabled for this source we
          # always recompute and never read/write Redis.
          unless cache_enabled?(data_source)
            return block.call
          end

          key = build_cache_key(data_source, endpoint, params)
          entry = read_entry(key)

          if entry && !should_early_refresh?(entry)
            record_hit(data_source)
            return entry[:payload]
          end

          ttl = ttl_for(endpoint)

          # Try to become the single recomputing caller for this key.
          if acquire_lock(key)
            begin
              record_miss(data_source) unless entry
              payload, delta = timed { block.call }
              write_entry(key, payload, ttl: ttl, delta: delta)
              payload
            ensure
              release_lock(key)
            end
          else
            # Lost the race. Briefly wait for the holder to publish, then serve
            # the freshest value we can. If we had a (stale) entry, serve it to
            # avoid a thundering recompute; otherwise recompute as a last resort.
            fresh = wait_for_value(key)
            if fresh
              record_hit(data_source)
              fresh[:payload]
            elsif entry
              record_hit(data_source)
              entry[:payload]
            else
              # No value materialised and nothing stale to serve: recompute
              # without caching to keep the caller unblocked. The lock holder
              # will populate the cache for the next caller.
              record_miss(data_source)
              block.call
            end
          end
        rescue ArgumentError
          # A missing block is a programming error, not a cache fault — let it surface
          # instead of being swallowed and turned into a nil.call NoMethodError.
          raise
        rescue => e
          Rails.logger.error "[ResponseCache] fetch failed for #{safe_slug(data_source, endpoint)}: #{e.message}"
          # Never let a cache fault break a fetch — fall back to direct compute.
          block.call
        end

        # Raw read. Returns the cached payload (Hash/Array per the canonical
        # FetchEnvelope data shape) or nil. Counts toward hit/miss metrics.
        def read(data_source:, endpoint:, params: {})
          return nil unless cache_enabled?(data_source)

          key = build_cache_key(data_source, endpoint, params)
          entry = read_entry(key)
          if entry
            record_hit(data_source)
            entry[:payload]
          else
            record_miss(data_source)
            nil
          end
        rescue => e
          Rails.logger.error "[ResponseCache] read failed: #{e.message}"
          nil
        end

        # Raw write with explicit TTL (seconds). Stores the XFetch metadata
        # (delta defaults to 0 for externally-written entries) alongside the
        # payload. Returns true on success.
        def write(data_source:, endpoint:, params: {}, payload:, ttl: nil)
          return false unless cache_enabled?(data_source)

          key = build_cache_key(data_source, endpoint, params)
          ttl_seconds = (ttl || ttl_for(endpoint)).to_i
          write_entry(key, payload, ttl: ttl_seconds, delta: 0.0)
          true
        rescue => e
          Rails.logger.error "[ResponseCache] write failed: #{e.message}"
          false
        end

        # Invalidate cached responses. Scope:
        #   - data_source + endpoint => deletes every param-variant for that
        #     endpoint (prefix delete on the slug pair).
        #   - data_source only       => deletes every endpoint + variant for the
        #     source.
        # Returns the number of keys deleted.
        def invalidate(data_source:, endpoint: nil)
          ds_id = id_of(data_source)
          pattern =
            if endpoint
              "#{REDIS_NAMESPACE}:#{ds_id}:#{slug_of(endpoint)}:*"
            else
              "#{REDIS_NAMESPACE}:#{ds_id}:*"
            end
          delete_by_pattern(pattern)
        rescue => e
          Rails.logger.error "[ResponseCache] invalidate failed: #{e.message}"
          0
        end

        # Aggregate metrics in the same shape as the prompt cache:
        # { hits:, misses:, total:, hit_rate: } (hit_rate as a percentage).
        def metrics
          hits = redis.get("#{METRICS_NAMESPACE}:hits")&.to_i || 0
          misses = redis.get("#{METRICS_NAMESPACE}:misses")&.to_i || 0
          total = hits + misses

          {
            hits: hits,
            misses: misses,
            total: total,
            hit_rate: total > 0 ? (hits.to_f / total * 100).round(1) : 0
          }
        end

        def reset_metrics!
          redis.del("#{METRICS_NAMESPACE}:hits")
          redis.del("#{METRICS_NAMESPACE}:misses")
        end

        private

        # --- Key construction -------------------------------------------------

        # Human-readable prefix (data_source_id + endpoint_slug) plus a SHA256
        # digest of [data_source_id, endpoint_slug, normalized_params]. The
        # readable prefix keeps prefix-based invalidation cheap; the digest keeps
        # the param-variant portion bounded and collision-resistant.
        def build_cache_key(data_source, endpoint, params)
          ds_id = id_of(data_source)
          slug = slug_of(endpoint)
          digest = Digest::SHA256.hexdigest(
            [ds_id, slug, normalized_params(params)].join("|")
          )
          "#{REDIS_NAMESPACE}:#{ds_id}:#{slug}:#{digest}"
        end

        # Stable canonical JSON for params so equivalent requests collapse to the
        # same key regardless of hash ordering or key symbol/string form.
        def normalized_params(params)
          deep_sort(params).to_json
        rescue StandardError
          params.to_s
        end

        def deep_sort(obj)
          case obj
          when Hash
            obj.each_with_object({}) { |(k, v), acc| acc[k.to_s] = deep_sort(v) }
                .sort.to_h
          when Array
            obj.map { |v| deep_sort(v) }
          else
            obj
          end
        end

        # --- Entry read/write (payload + XFetch metadata) ---------------------

        # Stored envelope: { "p" => payload, "d" => delta_seconds, "e" => expiry_epoch_ms }.
        def read_entry(key)
          raw = redis.get(key)
          return nil unless raw

          data = JSON.parse(raw)
          {
            payload: data["p"],
            delta: data["d"].to_f,
            expiry: data["e"].to_i
          }
        rescue JSON::ParserError
          nil
        end

        def write_entry(key, payload, ttl:, delta:)
          ttl_seconds = [ttl.to_i, 1].max
          expiry_ms = (Time.now.to_f * 1000).to_i + (ttl_seconds * 1000)
          envelope = { "p" => payload, "d" => delta.to_f, "e" => expiry_ms }
          redis.setex(key, ttl_seconds, envelope.to_json)
        end

        # --- XFetch probabilistic early refresh -------------------------------

        # gamma = delta * BETA * -ln(rand). Refresh early once now + gamma has
        # caught up to the hard expiry. Entries with no recorded cost (delta 0)
        # never trigger an early refresh — they simply expire.
        def should_early_refresh?(entry)
          delta = entry[:delta]
          return false if delta <= 0.0

          now_ms = (Time.now.to_f * 1000).to_i
          gamma_ms = delta * 1000 * XFETCH_BETA * -Math.log(rand)
          (now_ms + gamma_ms) >= entry[:expiry]
        end

        # --- Singleflight recompute lock --------------------------------------

        def lock_key(key)
          "#{LOCK_NAMESPACE}:#{key}"
        end

        # SET NX PX — atomic acquire with a safety TTL so a crashed holder
        # cannot permanently wedge the key.
        def acquire_lock(key)
          redis.set(lock_key(key), "1", nx: true, px: LOCK_TTL_SECONDS * 1000) ? true : false
        end

        def release_lock(key)
          redis.del(lock_key(key))
        rescue StandardError
          nil
        end

        # Poll for the value the lock holder is computing, up to a short budget.
        # Returns the entry once present, or nil on timeout.
        def wait_for_value(key)
          deadline = Time.now + LOCK_WAIT_TIMEOUT_S
          loop do
            entry = read_entry(key)
            return entry if entry
            return nil if Time.now >= deadline

            sleep(LOCK_POLL_INTERVAL_S)
          end
        end

        # --- Prefix deletion (invalidate) -------------------------------------

        # SCAN-based delete to avoid blocking Redis with KEYS on large keyspaces.
        def delete_by_pattern(pattern)
          deleted = 0
          cursor = "0"
          loop do
            cursor, keys = redis.scan(cursor, match: pattern, count: 500)
            unless keys.empty?
              redis.del(*keys)
              deleted += keys.size
            end
            break if cursor == "0"
          end
          deleted
        end

        # --- Metrics (mirrors PromptCacheService counter shape) ---------------

        def record_hit(data_source)
          bump_counter("#{METRICS_NAMESPACE}:hits")
          bump_counter("#{METRICS_NAMESPACE}:hits:#{id_of(data_source)}")
        end

        def record_miss(data_source)
          bump_counter("#{METRICS_NAMESPACE}:misses")
          bump_counter("#{METRICS_NAMESPACE}:misses:#{id_of(data_source)}")
        end

        def bump_counter(key)
          redis.incr(key)
          redis.expire(key, METRICS_TTL_SECONDS) if redis.ttl(key) < 0
        end

        # --- Helpers ----------------------------------------------------------

        # Per-source kill flag. Defaults to enabled when the flag is unset so the
        # cache works out of the box; toggle off per source via the feature flag.
        def cache_enabled?(data_source)
          Shared::FeatureFlagService.enabled?(:data_source_response_caching, data_source) ||
            Shared::FeatureFlagService.enabled?(:data_source_response_caching)
        rescue StandardError
          true
        end

        def ttl_for(endpoint)
          ttl = endpoint.respond_to?(:cache_ttl_seconds) ? endpoint.cache_ttl_seconds : nil
          (ttl && ttl.to_i.positive?) ? ttl.to_i : DEFAULT_TTL.to_i
        end

        def id_of(data_source)
          data_source.respond_to?(:id) ? data_source.id : data_source
        end

        def slug_of(endpoint)
          endpoint.respond_to?(:slug) ? endpoint.slug : endpoint
        end

        def safe_slug(data_source, endpoint)
          "#{id_of(data_source)}/#{slug_of(endpoint)}"
        rescue StandardError
          "unknown"
        end

        # Times a block, returning [result, elapsed_seconds].
        def timed
          started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          result = yield
          elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
          [result, elapsed]
        end

        def redis
          Powernode::Redis.client
        end
      end
    end
  end
end
