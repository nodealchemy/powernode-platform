# frozen_string_literal: true

module Ai
  module Learning
    class PromptCacheService
      DEFAULT_TTL = 5.minutes
      REDIS_NAMESPACE = "prompt_cache"
      METRICS_NAMESPACE = "prompt_cache_metrics"

      class << self
        def lookup(system_prompt:, user_prompt:, model_name:, temperature:)
          return nil unless Shared::FeatureFlagService.enabled?(:prompt_caching)

          key = build_cache_key(system_prompt, user_prompt, model_name, temperature)
          cached = redis.get(key)

          if cached
            record_hit(model_name)
            JSON.parse(cached)
          else
            record_miss(model_name)
            nil
          end
        rescue => e
          Rails.logger.error "[PromptCache] Lookup failed: #{e.message}"
          nil
        end

        def store(system_prompt:, user_prompt:, model_name:, temperature:, response:, ttl: DEFAULT_TTL)
          return unless Shared::FeatureFlagService.enabled?(:prompt_caching)

          key = build_cache_key(system_prompt, user_prompt, model_name, temperature)
          redis.setex(key, ttl.to_i, response.to_json)
        rescue => e
          Rails.logger.error "[PromptCache] Store failed: #{e.message}"
        end

        def invalidate(system_prompt:, user_prompt:, model_name:, temperature:)
          key = build_cache_key(system_prompt, user_prompt, model_name, temperature)
          redis.del(key)
        end

        def metrics(account_id: nil)
          hits = redis.get("#{METRICS_NAMESPACE}:hits")&.to_i || 0
          misses = redis.get("#{METRICS_NAMESPACE}:misses")&.to_i || 0
          total = hits + misses

          {
            hits: hits,
            misses: misses,
            total: total,
            hit_rate: total > 0 ? (hits.to_f / total * 100).round(1) : 0,
            estimated_savings_usd: estimated_savings(hits)
          }
        end

        def reset_metrics!
          redis.del("#{METRICS_NAMESPACE}:hits")
          redis.del("#{METRICS_NAMESPACE}:misses")
        end

        private

        def build_cache_key(system_prompt, user_prompt, model_name, temperature)
          content = "#{system_prompt}|#{user_prompt}|#{model_name}|#{temperature}"
          hash = Digest::SHA256.hexdigest(content)
          "#{REDIS_NAMESPACE}:#{hash}"
        end

        def record_hit(model_name)
          redis.incr("#{METRICS_NAMESPACE}:hits")
          redis.incr("#{METRICS_NAMESPACE}:hits:#{model_name}")
        end

        def record_miss(model_name)
          redis.incr("#{METRICS_NAMESPACE}:misses")
          redis.incr("#{METRICS_NAMESPACE}:misses:#{model_name}")
        end

        def estimated_savings(hit_count)
          # Average cost per LLM call ~ $0.01
          (hit_count * 0.01).round(2)
        end

        def redis
          @redis ||= Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
        end
      end
    end
  end
end
