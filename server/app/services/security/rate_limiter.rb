# frozen_string_literal: true

module Security
  class RateLimiter
    class RateLimitExceeded < StandardError
      attr_reader :limit, :window, :retry_after

      def initialize(limit:, window:, retry_after:)
        @limit = limit
        @window = window
        @retry_after = retry_after
        super("Rate limit exceeded: #{limit} requests per #{window} seconds. Retry after #{retry_after} seconds.")
      end
    end

    # Default rate limits by endpoint category
    RATE_LIMITS = {
      # Chat webhooks (external platform callbacks)
      chat_webhook: { limit: 100, window: 60 },

      # Chat message sending
      chat_send: { limit: 30, window: 60 },

      # Container execution
      container_execute: { limit: 10, window: 60 },

      # Community agent discovery
      community_discover: { limit: 50, window: 60 },

      # Federation requests
      federation_request: { limit: 20, window: 60 },

      # A2A task submission
      a2a_submit: { limit: 30, window: 60 },

      # General API calls
      api_default: { limit: 100, window: 60 }
    }.freeze

    # INCR and the window's EXPIRE in one atomic script (IMP-3fdaa94f6327).
    # This used to be INCR, then a separate EXPIRE only when the count was 1:
    # losing that one EXPIRE left a counter with no TTL, and a client past the
    # limit stayed limited forever.
    #
    # Window semantics are unchanged: a fixed window that starts at the first
    # request and is never extended by later ones. The TTL is set only when the
    # key has none (TTL -1), which is the count == 1 case and also heals a
    # counter an older process left without one. Lua rather than EXPIRE ... NX,
    # which needs Redis 7.0; this runs on any Redis with EVAL.
    INCREMENT_SCRIPT = <<~LUA
      local count = redis.call("INCR", KEYS[1])
      if redis.call("TTL", KEYS[1]) == -1 then
        redis.call("EXPIRE", KEYS[1], ARGV[1])
      end
      return count
    LUA

    class << self
      # Check and increment rate limit
      def check!(key:, category: :api_default, account_id: nil, custom_limit: nil)
        config = custom_limit || RATE_LIMITS[category] || RATE_LIMITS[:api_default]
        full_key = build_key(key, category, account_id)

        count = increment(full_key, config[:window])

        if count > config[:limit]
          ttl = redis.ttl(full_key)
          raise RateLimitExceeded.new(
            limit: config[:limit],
            window: config[:window],
            retry_after: ttl.positive? ? ttl : config[:window]
          )
        end

        {
          remaining: [ config[:limit] - count, 0 ].max,
          limit: config[:limit],
          reset_at: Time.current + redis.ttl(full_key).seconds
        }
      end

      # Get current usage without incrementing
      def usage(key:, category: :api_default, account_id: nil)
        config = RATE_LIMITS[category] || RATE_LIMITS[:api_default]
        full_key = build_key(key, category, account_id)

        count = redis.get(full_key).to_i
        ttl = redis.ttl(full_key)

        {
          used: count,
          remaining: [ config[:limit] - count, 0 ].max,
          limit: config[:limit],
          reset_at: ttl.positive? ? Time.current + ttl.seconds : nil
        }
      end

      # Reset rate limit for a key
      def reset!(key:, category: :api_default, account_id: nil)
        full_key = build_key(key, category, account_id)
        redis.del(full_key)
      end

      # Check if currently rate limited
      def limited?(key:, category: :api_default, account_id: nil)
        config = RATE_LIMITS[category] || RATE_LIMITS[:api_default]
        full_key = build_key(key, category, account_id)

        count = redis.get(full_key).to_i
        count >= config[:limit]
      end

      private

      def build_key(key, category, account_id)
        parts = [ "rate_limit", category ]
        parts << "account:#{account_id}" if account_id.present?
        parts << key
        parts.join(":")
      end

      def increment(key, window)
        redis.eval(INCREMENT_SCRIPT, keys: [ key ], argv: [ window.to_i ])
      end

      def redis
        Powernode::Redis.pooled
      end
    end
  end
end
