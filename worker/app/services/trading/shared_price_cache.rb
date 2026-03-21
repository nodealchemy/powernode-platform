# frozen_string_literal: true

module Trading
  # Redis-backed shared price cache for concurrent strategy runners.
  # When multiple strategies trade the same pair on the same venue,
  # the first runner to fetch market data stores it here; subsequent
  # runners within the TTL window read from cache instead of hitting
  # the backend API again. [H2, M3, #7]
  class SharedPriceCache
    TTL = 5 # seconds — prices stale quickly
    KEY_PREFIX = "trading:shared_price"

    class << self
      def fetch(venue_id, pair)
        key = cache_key(venue_id, pair)
        raw = redis { |conn| conn.get(key) }
        return nil unless raw

        @hits = (@hits || 0) + 1
        JSON.parse(raw, symbolize_names: true)
      rescue StandardError
        nil
      end

      def store(venue_id, pair, data)
        key = cache_key(venue_id, pair)
        redis { |conn| conn.set(key, data.to_json, ex: TTL) }
        @stores = (@stores || 0) + 1
        true
      rescue StandardError
        false
      end

      def fetch_or_compute(venue_id, pair)
        cached = fetch(venue_id, pair)
        return cached if cached

        @misses = (@misses || 0) + 1
        data = yield
        store(venue_id, pair, data) if data
        data
      end

      def hit_count
        @hits || 0
      end

      def miss_count
        @misses || 0
      end

      def store_count
        @stores || 0
      end

      private

      def cache_key(venue_id, pair)
        "#{KEY_PREFIX}:#{venue_id}:#{pair}"
      end

      def redis(&block)
        if defined?(Sidekiq) && Sidekiq.respond_to?(:redis)
          Sidekiq.redis(&block)
        else
          conn = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/1"))
          begin
            yield conn
          ensure
            conn.close
          end
        end
      end
    end
  end
end
