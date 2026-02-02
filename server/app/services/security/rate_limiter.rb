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
        count = redis.incr(key)
        redis.expire(key, window) if count == 1
        count
      end

      def redis
        @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
      end
    end
  end
end
