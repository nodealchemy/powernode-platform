# frozen_string_literal: true

module Security
  # Durable, cross-process state for RequestInspector's DDoS controls.
  #
  # WHY THIS EXISTS RATHER THAN Rails.cache. Every counter and every IP block
  # used to be a Rails.cache key, and the hub pins CACHE_STORE=memory_store
  # (extensions/system/modules/powernode-hub-backend/manifest.yaml) — a pin the
  # manifest documents as a deliberate live-hub deploy decision, not an
  # oversight. MemoryStore is per PROCESS, so:
  #
  #   - a block written by one puma worker was invisible to the others, i.e. a
  #     blocked attacker still reached the app on every worker but one;
  #   - the suspicious-request counter that DECIDES a block was also per worker,
  #     so the effective threshold was suspicious_request_limit x worker count;
  #   - every block and every offense count vanished on restart, which is
  #     exactly when an attacker retries.
  #
  # The tell was already in the tree: #remaining_block_time read the block's TTL
  # through Powernode::CacheRedis, which returns nil unless Rails.cache IS a
  # Redis store — so on the hub every Retry-After was the hardcoded fallback.
  #
  # This store talks to Redis DIRECTLY (Powernode::Redis), independent of
  # whatever Rails.cache is configured to be, so the CACHE_STORE pin stays put.
  # The hub-backend module already requires powernode/redis and sets REDIS_URL;
  # the worker uses the same instance.
  #
  # FAIL OPEN, ALWAYS. Every method rescues and answers as if the IP were
  # unknown. A Redis outage must never 403 legitimate traffic, and it must never
  # raise out of Rack middleware — this runs ahead of routing, so an exception
  # here is a blank 500 with no controller log. The cost of failing open is that
  # blocking stops while Redis is down, which is the same posture the middleware
  # already takes for any error (RequestInspector#call rescues to @app.call).
  module IpBlockStore
    PREFIX = "ddos"

    BLOCK_PREFIX        = "#{PREFIX}:block:"
    OFFENSES_PREFIX     = "#{PREFIX}:offenses:"
    SUSPICIOUS_PREFIX   = "#{PREFIX}:suspicious:"
    RAPID_PREFIX        = "#{PREFIX}:rapid:"
    RAPID_FLAG_PREFIX   = "#{PREFIX}:rapid_flagged:"

    # How long an offense count (the progressive-penalty memory) outlives the
    # block it produced. Unchanged from the Rails.cache implementation.
    OFFENSE_TTL_SECONDS = 7 * 24 * 60 * 60

    # Cap on how many blocked IPs the operator listing walks. A SCAN over a
    # very large block set must not become the slow query that takes the admin
    # page down; the listing says when it truncated.
    MAX_LISTED_BLOCKS = 500

    module_function

    # === Blocks ===

    def blocked?(ip)
      return false if ip.blank?

      with { |redis| redis.exists?(BLOCK_PREFIX + ip.to_s) } || false
    end

    # Writes the block with its own expiry. `duration_seconds` is the caller's
    # already-computed penalty (see RequestInspector#calculate_block_duration).
    def block!(ip, duration_seconds:)
      return false if ip.blank?

      seconds = duration_seconds.to_i
      return false unless seconds.positive?

      with { |redis| redis.set(BLOCK_PREFIX + ip.to_s, Time.current.to_i.to_s, ex: seconds) }
      true
    end

    # Lifts a block early. Returns true only when a block was actually present,
    # so the operator surface can distinguish "unblocked" from "was not blocked"
    # instead of reporting success either way.
    def unblock!(ip)
      return false if ip.blank?

      (with { |redis| redis.del(BLOCK_PREFIX + ip.to_s) }).to_i.positive?
    end

    # Remaining block seconds, or nil when the IP is not blocked / Redis is
    # unreachable. Redis answers -2 for a missing key and -1 for one with no
    # expiry; neither is a duration, so both read as nil.
    def block_ttl(ip)
      return nil if ip.blank?

      ttl = with { |redis| redis.ttl(BLOCK_PREFIX + ip.to_s) }
      return nil if ttl.nil? || ttl.negative?

      ttl
    end

    # Every currently blocked IP with its remaining time and offense history.
    # Truncated at MAX_LISTED_BLOCKS; `truncated` says so rather than silently
    # returning a partial answer (an absence check that is quietly capped is
    # worse than no listing).
    def blocked_ips(limit: MAX_LISTED_BLOCKS)
      rows = []
      truncated = false

      with do |redis|
        redis.scan_each(match: "#{BLOCK_PREFIX}*") do |key|
          if rows.size >= limit
            truncated = true
            break
          end
          ip = key.delete_prefix(BLOCK_PREFIX)
          rows << {
            ip: ip,
            ttl_seconds: [ redis.ttl(key), 0 ].max,
            offense_count: redis.get(OFFENSES_PREFIX + ip).to_i,
            suspicious_count: redis.get(SUSPICIOUS_PREFIX + ip).to_i
          }
        end
      end

      { blocks: rows.sort_by { |r| -r[:ttl_seconds] }, truncated: truncated }
    end

    # === Counters ===
    #
    # INCR + EXPIRE rather than read-modify-write. The old implementation read
    # the value, added one and wrote it back, which loses increments under
    # concurrency — on the exact traffic shape (a flood) the counter exists to
    # measure. EXPIRE is re-applied on every bump, matching the previous
    # `expires_in:` on every write.

    def bump_suspicious(ip, ttl_seconds:)
      bump(SUSPICIOUS_PREFIX + ip.to_s, ttl_seconds)
    end

    def suspicious_count(ip)
      read_count(SUSPICIOUS_PREFIX + ip.to_s)
    end

    def bump_rapid(ip, ttl_seconds:)
      bump(RAPID_PREFIX + ip.to_s, ttl_seconds)
    end

    def rapid_count(ip)
      read_count(RAPID_PREFIX + ip.to_s)
    end

    def offense_count(ip)
      read_count(OFFENSES_PREFIX + ip.to_s)
    end

    def bump_offense(ip)
      bump(OFFENSES_PREFIX + ip.to_s, OFFENSE_TTL_SECONDS)
    end

    # Claims the current rapid-request window for this IP: true for the FIRST
    # caller in the window, false afterwards. SET NX EX is atomic, so two puma
    # threads racing on the same burst cannot both score a hit — the read-then-
    # write version could, which is how one page load turned into several
    # suspicious hits.
    def claim_rapid_window!(ip, ttl_seconds:)
      return false if ip.blank?

      with { |redis| redis.set(RAPID_FLAG_PREFIX + ip.to_s, "1", nx: true, ex: ttl_seconds.to_i) } ? true : false
    end

    # Test/operator seam: drop every key this store owns for one IP.
    def reset!(ip)
      return if ip.blank?

      with do |redis|
        redis.del(
          BLOCK_PREFIX + ip.to_s, OFFENSES_PREFIX + ip.to_s, SUSPICIOUS_PREFIX + ip.to_s,
          RAPID_PREFIX + ip.to_s, RAPID_FLAG_PREFIX + ip.to_s
        )
      end
    end

    # === Plumbing ===

    def bump(key, ttl_seconds)
      value = with do |redis|
        count = redis.incr(key)
        redis.expire(key, ttl_seconds.to_i) if ttl_seconds.to_i.positive?
        count
      end
      value.to_i
    end

    def read_count(key)
      with { |redis| redis.get(key) }.to_i
    end

    # A pool rather than Powernode::Redis.client: this runs on every request in
    # a threaded puma, and the memoized single client serialises them all
    # through one Monitor.
    def pool
      @pool ||= ConnectionPool.new(size: pool_size, timeout: 1) { ::Powernode::Redis.new_client }
    end

    def pool_size
      Integer(ENV.fetch("DDOS_REDIS_POOL_SIZE", ENV.fetch("RAILS_MAX_THREADS", "5")))
    rescue ArgumentError, TypeError
      5
    end

    # Drops the pool so a reconfigured Redis URL (or a forked process) builds
    # fresh connections. Mirrors Powernode::Redis.reconfigure!.
    def reset_pool!
      @pool&.shutdown { |conn| conn.close rescue nil }
      @pool = nil
    end

    def with(&block)
      pool.with(&block)
    rescue StandardError => e
      Rails.logger.warn("[IpBlockStore] redis unavailable (failing open): #{e.class}: #{e.message}")
      nil
    end
  end
end
