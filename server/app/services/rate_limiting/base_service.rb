# frozen_string_literal: true

module RateLimiting
  class BaseService
    class << self
      # Get current rate limit statistics
      def get_statistics
        {
          enabled: ENV["DISABLE_RATE_LIMITING"] != "true",
          current_violations: count_current_violations,
          active_limits: count_active_limits,
          configuration: get_current_configuration,
          tier_statistics: RateLimiting::TieredService.tier_statistics
        }
      rescue RateLimiting::UnsupportedStore => e
        # Never zero counts: the configuration is still true, the counters are unknown.
        {
          enabled: ENV["DISABLE_RATE_LIMITING"] != "true",
          supported: false,
          error: e.message,
          configuration: get_current_configuration
        }
      end

      # Get tier-specific statistics for an account
      def get_account_statistics(account)
        return nil unless account

        {
          account_id: account.id,
          account_name: account.name,
          tier_info: RateLimiting::TieredService.account_usage(account),
          rate_limited: RateLimiting::TieredService.account_rate_limited?(account),
          limits: RateLimiting::TieredService.tier_config(
            RateLimiting::TieredService.tier_for_account(account)
          )
        }
      end

      # Override tier for an account
      def override_account_tier(account, tier, duration: nil)
        RateLimiting::TieredService.override_tier(account, tier, duration: duration)
      end

      # Clear tier override for an account
      def clear_account_tier_override(account)
        RateLimiting::TieredService.clear_tier_override(account)
      end

      # Clear rate limits for a specific IP or user (numeric id or UUID). Returns the number of
      # counters deleted. Raises ArgumentError for an identifier of neither kind and UnsupportedStore
      # when the counters' Redis cannot be reached.
      def clear_limits_for(identifier)
        subject = Security::RateLimitKey.subject_for(identifier)
        raise ArgumentError, "Invalid identifier: #{identifier}" unless subject

        keys_cleared = 0
        with_counter_redis do |redis|
          scan_batches(redis, Security::RateLimitKey.pattern_for(subject)) do |keys|
            owned = keys.select { |key| Security::RateLimitKey.parse(key)&.fetch(:subject) == subject }
            if owned.any?
              redis.del(*owned.map { |key| Security::RateLimitKey.config_key(key) })
              keys_cleared += redis.del(*owned)
            end
          end
        end
        keys_cleared
      end

      # Check if an identifier is currently rate limited. false for an identifier of neither kind.
      def rate_limited?(identifier)
        subject = Security::RateLimitKey.subject_for(identifier)
        return false unless subject

        found = false
        with_counter_redis do |redis|
          scan_batches(redis, Security::RateLimitKey.pattern_for(subject)) do |keys|
            counters_and_ttls(redis, keys).each do |key, (current_count, _ttl, cfg)|
              parsed = Security::RateLimitKey.parse(key)
              next unless parsed && parsed[:subject] == subject

              limit = limit_for(parsed, cfg)
              if limit && current_count >= limit
                found = true
                break
              end
            end
            break if found
          end
        end
        found
      end

      # Detailed rate limit info for an identifier, keyed by category (suffixed with the account when
      # the counter is account-scoped).
      def get_limit_info(identifier)
        subject = Security::RateLimitKey.subject_for(identifier)
        return {} unless subject

        limits = {}
        with_counter_redis do |redis|
          scan_batches(redis, Security::RateLimitKey.pattern_for(subject)) do |keys|
            counters_and_ttls(redis, keys).each do |key, (current_count, ttl, cfg)|
              parsed = Security::RateLimitKey.parse(key)
              next unless parsed && parsed[:subject] == subject

              limit = limit_for(parsed, cfg)
              next unless limit

              label = parsed[:account_id] ? "#{parsed[:category]}:account:#{parsed[:account_id]}" : parsed[:category]
              limits[label] = {
                current: current_count,
                limit: limit,
                remaining: [ limit - current_count, 0 ].max,
                reset_in: ttl > 0 ? ttl : 0
              }
            end
          end
        end

        limits
      end

      # Every counter at or over its limit, worst first. Raises UnsupportedStore like the other readers.
      def recent_violations
        found = []
        with_counter_redis do |redis|
          scan_batches(redis, Security::RateLimitKey::ALL) do |keys|
            counters_and_ttls(redis, keys).each do |key, (current_count, _ttl, cfg)|
              parsed = Security::RateLimitKey.parse(key)
              limit = parsed && limit_for(parsed, cfg)
              next unless limit && current_count >= limit

              found << {
                endpoint: parsed[:category],
                identifier: parsed[:subject],
                account_id: parsed[:account_id],
                count: current_count,
                limit: limit,
                timestamp: Time.current.iso8601 # the counter carries no timestamp; this is when it was read
              }
            end
          end
        end
        found.sort_by { |v| -v[:count] }
      end

      # Temporarily disable rate limiting (for maintenance, etc.)
      def disable_temporarily(duration_minutes = 60)
        Rails.cache.write(
          "rate_limiting_temporarily_disabled",
          true,
          expires_in: duration_minutes.minutes
        )
      end

      # Check if rate limiting is temporarily disabled
      def temporarily_disabled?
        Rails.cache.read("rate_limiting_temporarily_disabled") || false
      end

      # Re-enable rate limiting
      def re_enable
        Rails.cache.delete("rate_limiting_temporarily_disabled")
      end

      private

      SCAN_COUNT = 1000
      READ_BATCH = 500

      # Cursor-based SCAN (never KEYS), handed to the block in slices so the per-key reads can be
      # batched. A `break` in the block stops the scan.
      def scan_batches(redis, pattern, &block)
        redis.scan_each(match: pattern, count: SCAN_COUNT).each_slice(READ_BATCH, &block)
      end

      # { key => [counter, ttl, configured_limit] } for the keys in ONE pipelined round trip. Counters
      # are raw integers, so GET.to_i is what read_counter returned. configured_limit is the limit a
      # custom_limit check! stored beside the counter (nil for a default-limit counter).
      def counters_and_ttls(redis, keys)
        replies = redis.pipelined do |pipe|
          keys.each do |key|
            pipe.get(key)
            pipe.ttl(key)
            pipe.get(Security::RateLimitKey.config_key(key))
          end
        end
        keys.each_with_index.to_h do |key, i|
          configured = replies[3 * i + 2].to_i
          [ key, [ replies[3 * i].to_i, replies[3 * i + 1].to_i, (configured if configured.positive?) ] ]
        end
      end

      # Runs the block with a connection to the Redis Security::RateLimiter writes its counters to
      # (Powernode::Redis), independent of whatever Rails.cache is. UnsupportedStore when it is down.
      def with_counter_redis(&block)
        Powernode::Redis.with(&block)
      rescue ::Redis::BaseConnectionError, ::ConnectionPool::TimeoutError => e
        Rails.logger.error "Rate limit counters unreachable: #{e.class}: #{e.message}"
        raise RateLimiting::UnsupportedStore
      end

      def count_current_violations
        violations = 0
        with_counter_redis do |redis|
          scan_batches(redis, Security::RateLimitKey::ALL) do |keys|
            counters_and_ttls(redis, keys).each do |key, (current_count, _ttl, cfg)|
              parsed = Security::RateLimitKey.parse(key)
              limit = parsed && limit_for(parsed, cfg)
              violations += 1 if limit && current_count >= limit
            end
          end
        end
        violations
      end

      def count_active_limits
        count = 0
        with_counter_redis do |redis|
          scan_batches(redis, Security::RateLimitKey::ALL) { |keys| count += keys.size }
        end
        count
      end

      def get_current_configuration
        rate_limit_keys = %w[
          api_requests_per_minute login_attempts_per_hour registration_attempts_per_hour
          password_reset_attempts_per_hour email_verification_attempts_per_hour
          authenticated_requests_per_hour impersonation_attempts_per_hour
          webhook_requests_per_minute websocket_connections_per_minute
        ]
        limits = rate_limit_keys.each_with_object({}) do |key, hash|
          hash[key.to_sym] = Admin::SystemSettings.rate_limit(key)
        end

        {
          enabled: ENV["DISABLE_RATE_LIMITING"] != "true",
          limits: limits
        }
      end

      # The limit a counter is held to: the one its check! stored beside it (a custom_limit), else its
      # category's default.
      def limit_for(parsed, configured)
        configured || limit_for_category(parsed[:category])
      end

      # The limit a counter's category is held to: the writer's own table first (the category is a
      # Security::RateLimiter::RATE_LIMITS key), then the admin-configured limit for a legacy
      # controller-named category. nil when neither knows it.
      def limit_for_category(category)
        known = Security::RateLimiter::RATE_LIMITS.find { |name, _| name.to_s == category }
        return known.last[:limit] if known

        Admin::SystemSettings.rate_limit(determine_limit_type_for_controller(category))
      end

      def determine_limit_type_for_controller(controller_name)
        case controller_name
        when "sessions"
          "login_attempts_per_hour"
        when "registrations"
          "registration_attempts_per_hour"
        when "passwords"
          "password_reset_attempts_per_hour"
        when "email_verifications"
          "email_verification_attempts_per_hour"
        when "webhooks"
          "webhook_requests_per_minute"
        when "impersonation_sessions"
          "impersonation_attempts_per_hour"
        else
          "api_requests_per_minute"
        end
      end
    end
  end
end
