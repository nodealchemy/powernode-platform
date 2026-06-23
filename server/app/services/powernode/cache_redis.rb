# frozen_string_literal: true

module Powernode
  # Access the raw Redis client backing the Rails cache store.
  #
  # In Rails 8, ActiveSupport::Cache::RedisCacheStore#redis returns a
  # ConnectionPool (the connection_pool gem wraps it by default), so Redis
  # commands such as `scan_each` / `ttl` cannot be invoked on `Rails.cache.redis`
  # directly — they raise NoMethodError on the pool. This helper checks out a
  # pooled connection and yields the underlying client. It also degrades safely
  # when the cache store has no Redis backend (e.g. :memory_store in test/dev),
  # in which case the block is skipped and `nil` is returned.
  module CacheRedis
    module_function

    # Yields a raw Redis client. Returns the block's value, or nil when the
    # cache store exposes no Redis backend (callers should treat nil as "no data").
    def with
      store = Rails.cache
      return nil unless store.respond_to?(:redis)

      redis = store.redis
      if defined?(ConnectionPool) && redis.is_a?(ConnectionPool)
        redis.with { |conn| yield conn }
      else
        yield redis
      end
    end

    # TTL (in seconds) for a raw cache key, or nil when there is no Redis backend.
    def ttl(key)
      with { |redis| redis.ttl(key) }
    end

    # Iterate raw cache keys matching a glob pattern, yielding each key to the
    # block. `break` inside the block stops the scan. No-op (returns nil) when
    # there is no Redis backend.
    def scan_each(match:, &block)
      with { |redis| redis.scan_each(match: match, &block) }
    end
  end
end
