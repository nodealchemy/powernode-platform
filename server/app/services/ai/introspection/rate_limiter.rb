# frozen_string_literal: true

module Ai
  module Introspection
    class RateLimiter
      DEFAULT_MAX_CALLS = 10
      DEFAULT_WINDOW_SECONDS = 60
      REDIS_NAMESPACE = "ai:introspection:rate_limit"

      class RateLimitExceeded < StandardError
        attr_reader :retry_after

        def initialize(retry_after:)
          @retry_after = retry_after
          super("Rate limit exceeded. Retry after #{retry_after} seconds.")
        end
      end

      class << self
        def check!(agent_id:, max_calls: DEFAULT_MAX_CALLS, window: DEFAULT_WINDOW_SECONDS)
          key = rate_limit_key(agent_id)
          now = Time.current.to_f

          redis.multi do |pipeline|
            pipeline.zremrangebyscore(key, "-inf", now - window)
            pipeline.zadd(key, now, "#{now}:#{SecureRandom.hex(4)}")
            pipeline.zcard(key)
            pipeline.expire(key, window)
          end => results

          count = results[2]
          if count > max_calls
            redis.zrem(key, "#{now}:#{SecureRandom.hex(4)}")
            oldest = redis.zrange(key, 0, 0, with_scores: true).first
            retry_after = oldest ? (oldest[1] + window - now).ceil : window
            raise RateLimitExceeded.new(retry_after: [retry_after, 1].max)
          end

          { remaining: max_calls - count, reset_in: window }
        end

        def remaining(agent_id:, max_calls: DEFAULT_MAX_CALLS, window: DEFAULT_WINDOW_SECONDS)
          key = rate_limit_key(agent_id)
          now = Time.current.to_f

          redis.zremrangebyscore(key, "-inf", now - window)
          count = redis.zcard(key)

          [max_calls - count, 0].max
        end

        def reset!(agent_id:)
          redis.del(rate_limit_key(agent_id))
        end

        private

        def rate_limit_key(agent_id)
          "#{REDIS_NAMESPACE}:#{agent_id}"
        end

        def redis
          @redis ||= Powernode::Redis.client
        end
      end
    end
  end
end
