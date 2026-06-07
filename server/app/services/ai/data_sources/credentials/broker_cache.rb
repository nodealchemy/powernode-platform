# frozen_string_literal: true

require "json"

module Ai
  module DataSources
    module Credentials
      # Redis-backed cache for SHORT-LIVED brokered credentials, with clock-skew
      # trimming and singleflight so a swarm hitting expiry does not hammer the
      # token endpoint / STS.
      #
      # WHY a cache: brokered creds are exchanged from an external authority just
      # before the signed fetch (see BaseBroker). Without a cache, every request
      # would call AssumeRole / the OAuth token_url / the Vault dynamic engine —
      # rate-limited, slow, and a thundering herd at expiry. We cache the acquired
      # material in Redis for (lease - skew) seconds and reuse it until then.
      #
      # SECURITY: the cached value is short-lived, scoped secret material in Redis.
      # This is acceptable (ephemeral, account/source-scoped, expires automatically)
      # but it is NEVER logged. Only the cache KEY (a non-secret digest) and the
      # outcome appear in any log line. The block's material Hash is serialized as
      # JSON for storage and parsed back on a hit; callers wrap it in a
      # BrokeredCredential which itself never logs values.
      #
      # FAIL-OPEN: any Redis error => just run the block and return its material
      # uncached. A cache outage must never break the fetch pipeline.
      #
      # NO SLEEPING: singleflight is a SETNX recompute lock with a short TTL. If the
      # lock is NOT acquired (another worker is already recomputing), we compute the
      # value ourselves WITHOUT caching rather than sleeping — Kernel#sleep is
      # forbidden in this pipeline. The brief duplicate compute is cheap and bounded;
      # a sleep+retry storm is not.
      module BrokerCache
        module_function

        # Redis key namespace for all brokered-credential cache + lock keys.
        NAMESPACE = "ds_cred_broker:"

        # Floor on the stored TTL. Even a credential whose (lease - skew) computes
        # to <= 0 is cached for this long so a singleflight burst at expiry still
        # collapses onto one acquisition; the next request re-acquires.
        MIN_TTL = 5

        # Recompute-lock TTL (seconds). Bounds how long a crashed acquirer can hold
        # the singleflight lock before another worker is allowed to recompute.
        LOCK_TTL = 10

        # Acquire-or-fetch a brokered credential's material.
        #
        # On a HIT: returns the cached material Hash (string keys, as stored).
        # On a MISS: runs +block+, which MUST return:
        #   { material: Hash, ttl_seconds: Integer }
        #   - material:    the acquired secret material (stored as JSON)
        #   - ttl_seconds: the LEASE seconds already net of skew (use
        #                  .ttl_with_skew to derive this from an absolute expiry).
        # The material is cached for max(ttl_seconds, MIN_TTL) and returned.
        #
        # Singleflight: only the SETNX lock winner writes the cache; a contended
        # caller still computes (no sleep) but does not write. A block that returns
        # a non-positive ttl_seconds is treated as "do not cache" (returns material
        # without writing) — brokers signal "uncacheable" that way.
        #
        # @param cache_key [String] caller-supplied stable key (e.g. a digest of
        #   broker type + source id + base-credential fingerprint). Namespaced here.
        # @yieldreturn [Hash{Symbol=>Object}] { material:, ttl_seconds: }
        # @return [Hash, nil] the material Hash, or nil if the block yielded none.
        def fetch(cache_key, &block)
          raise ArgumentError, "block required" unless block

          redis = redis_client
          full_key = namespaced(cache_key)

          # Cache READ (fail-open): safe_get + parse rescue internally, so a Redis
          # fault here simply falls through to a single compute below.
          if redis
            cached = safe_get(redis, full_key)
            parsed = cached && parse(cached)
            return parsed if parsed
          end

          # Compute EXACTLY ONCE, OUTSIDE any rescue. A failed exchange MUST
          # propagate to the broker's own fail-safe (BaseBroker#acquire), never be
          # retried here — retrying would double the upstream call (AssumeRole / the
          # OAuth token endpoint / the Vault dynamic engine) and defeat singleflight.
          # The cache WRITE below is fully fail-open (store_with_singleflight and its
          # helpers all rescue internally), so it can never raise back into this
          # method and re-run the block.
          computed = block.call
          material, ttl = unwrap(computed)
          return material if material.nil?
          return material if redis.nil? # fail-open: nothing to cache into
          return material if ttl <= 0 # broker signaled uncacheable

          store_with_singleflight(redis, full_key, cache_key, material, ttl)
          material
        end

        # Derive the lease seconds to cache from an ABSOLUTE expiry, trimmed by a
        # safety skew so the cached credential is dropped slightly before the
        # upstream actually expires it (avoids signing with a just-expired token).
        # Floored at 0 (the caller / .fetch applies MIN_TTL).
        #
        # @param expires_at [Time, nil] absolute lease expiry.
        # @param skew_seconds [Integer] safety margin to subtract.
        # @return [Integer] seconds, >= 0. Returns 0 when expires_at is nil.
        def ttl_with_skew(expires_at:, skew_seconds: 0)
          return 0 if expires_at.nil?

          remaining = (expires_at.to_time - Time.current).to_i - skew_seconds.to_i
          remaining.positive? ? remaining : 0
        rescue StandardError
          0
        end

        # ----------------------------------------------------------------------
        # internals
        # ----------------------------------------------------------------------

        def namespaced(cache_key)
          "#{NAMESPACE}#{cache_key}"
        end

        # Singleflight write: the SETNX lock winner writes the value; a contended
        # caller skips the write (it already computed its own copy to return). Lock
        # is best-effort and self-expires via LOCK_TTL.
        def store_with_singleflight(redis, full_key, cache_key, material, ttl)
          ttl_final = [ttl.to_i, MIN_TTL].max
          payload = JSON.generate(material)

          if acquire_lock(redis, cache_key)
            begin
              safe_setex(redis, full_key, ttl_final, payload)
            ensure
              release_lock(redis, cache_key)
            end
          else
            # Another worker is acquiring concurrently. Do NOT sleep; just opportun-
            # istically populate if still empty so the herd converges, but never block.
            safe_setex(redis, full_key, ttl_final, payload) unless safe_get(redis, full_key)
          end
        end

        def lock_key(cache_key)
          "#{NAMESPACE}lock:#{cache_key}"
        end

        # SETNX + EXPIRE recompute lock. Returns true iff this caller won the lock.
        def acquire_lock(redis, cache_key)
          key = lock_key(cache_key)
          # set ... nx: true, ex: LOCK_TTL is atomic on modern redis-rb; fall back
          # to SETNX+EXPIRE if the kwargs form is unavailable.
          won = redis.set(key, "1", nx: true, ex: LOCK_TTL)
          won == true || won == "OK"
        rescue ArgumentError
          if redis.setnx(lock_key(cache_key), "1")
            redis.expire(lock_key(cache_key), LOCK_TTL)
            true
          else
            false
          end
        rescue StandardError
          # On any lock error, behave as the contended path (no write ownership).
          false
        end

        def release_lock(redis, cache_key)
          redis.del(lock_key(cache_key))
        rescue StandardError
          nil
        end

        def safe_get(redis, key)
          redis.get(key)
        rescue StandardError
          nil
        end

        def safe_setex(redis, key, ttl, value)
          redis.setex(key, ttl, value)
        rescue StandardError => e
          Rails.logger.warn("[Credentials::BrokerCache] cache write skipped: #{e.class}")
          nil
        end

        # Parse stored JSON back to a material Hash (string keys). A corrupt entry
        # is treated as a miss (returns nil).
        def parse(json)
          parsed = JSON.parse(json)
          parsed.is_a?(Hash) ? parsed : nil
        rescue JSON::ParserError
          nil
        end

        # Normalize a block result into [material_hash_or_nil, ttl_int].
        def unwrap(result)
          return [nil, 0] unless result.is_a?(Hash)

          material = result[:material] || result["material"]
          ttl = (result[:ttl_seconds] || result["ttl_seconds"]).to_i
          material = material.is_a?(Hash) ? material : nil
          [material, ttl]
        end

        def redis_client
          Powernode::Redis.client
        rescue StandardError
          nil
        end

        private_class_method :namespaced, :store_with_singleflight, :lock_key,
                             :acquire_lock, :release_lock, :safe_get, :safe_setex,
                             :parse, :unwrap, :redis_client
      end
    end
  end
end
