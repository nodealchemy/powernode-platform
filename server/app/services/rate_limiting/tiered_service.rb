# frozen_string_literal: true

module RateLimiting
  class TieredService
    # =========================================================================
    # RATE LIMIT TIERS
    # =========================================================================
    # Each tier defines rate limits per minute/hour for different endpoint categories

    TIERS = {
      free: {
        name: "Free",
        api_requests_per_minute: 30,
        api_requests_per_hour: 500,
        authenticated_requests_per_minute: 60,
        authenticated_requests_per_hour: 1000,
        heavy_requests_per_hour: 50,      # AI, exports, bulk operations
        webhook_requests_per_minute: 10,
        websocket_connections_per_minute: 5,
        file_uploads_per_hour: 20,
        burst_allowance: 1.2  # 20% burst allowance
      },
      starter: {
        name: "Starter",
        api_requests_per_minute: 100,
        api_requests_per_hour: 2000,
        authenticated_requests_per_minute: 200,
        authenticated_requests_per_hour: 5000,
        heavy_requests_per_hour: 200,
        webhook_requests_per_minute: 30,
        websocket_connections_per_minute: 10,
        file_uploads_per_hour: 100,
        burst_allowance: 1.3
      },
      professional: {
        name: "Professional",
        api_requests_per_minute: 300,
        api_requests_per_hour: 10_000,
        authenticated_requests_per_minute: 500,
        authenticated_requests_per_hour: 20_000,
        heavy_requests_per_hour: 500,
        webhook_requests_per_minute: 100,
        websocket_connections_per_minute: 30,
        file_uploads_per_hour: 500,
        burst_allowance: 1.5
      },
      enterprise: {
        name: "Enterprise",
        api_requests_per_minute: 1000,
        api_requests_per_hour: 50_000,
        authenticated_requests_per_minute: 2000,
        authenticated_requests_per_hour: 100_000,
        heavy_requests_per_hour: 2000,
        webhook_requests_per_minute: 500,
        websocket_connections_per_minute: 100,
        file_uploads_per_hour: 2000,
        burst_allowance: 2.0
      },
      unlimited: {
        name: "Unlimited",
        api_requests_per_minute: nil,  # nil = no limit
        api_requests_per_hour: nil,
        authenticated_requests_per_minute: nil,
        authenticated_requests_per_hour: nil,
        heavy_requests_per_hour: nil,
        webhook_requests_per_minute: nil,
        websocket_connections_per_minute: nil,
        file_uploads_per_hour: nil,
        burst_allowance: nil
      }
    }.freeze

    # =========================================================================
    # ENDPOINT COSTS
    # =========================================================================
    # Different endpoints have different "costs" - heavy operations count more

    ENDPOINT_COSTS = {
      # Standard operations (cost: 1)
      standard: {
        cost: 1,
        patterns: [
          %r{^/api/v1/auth/},
          %r{^/api/v1/users$},
          %r{^/api/v1/account$},
          %r{^/api/v1/plans$},
          %r{^/api/v1/roles$}
        ]
      },

      # Read operations (cost: 1)
      read: {
        cost: 1,
        methods: [ "GET", "HEAD", "OPTIONS" ]
      },

      # Write operations (cost: 2)
      write: {
        cost: 2,
        methods: [ "POST", "PUT", "PATCH", "DELETE" ]
      },

      # Heavy operations (cost: 5)
      heavy: {
        cost: 5,
        patterns: [
          %r{^/api/v1/ai_},
          %r{^/api/v1/workflows},
          %r{^/api/v1/reports},
          %r{^/api/v1/analytics},
          %r{^/api/v1/data_export},
          %r{^/api/v1/bulk_}
        ]
      },

      # File operations (cost: 3)
      file: {
        cost: 3,
        patterns: [
          %r{^/api/v1/files},
          %r{^/api/v1/file_}
        ]
      },

      # Webhook operations (cost: 2)
      webhook: {
        cost: 2,
        patterns: [
          %r{^/api/v1/webhook}
        ]
      },

      # Admin operations (cost: 1, but tracked separately)
      admin: {
        cost: 1,
        patterns: [
          %r{^/api/v1/admin}
        ]
      }
    }.freeze

    class << self
      # =========================================================================
      # TIER RESOLUTION
      # =========================================================================

      # Get the rate limit tier for an account
      def tier_for_account(account)
        return :free unless account
        return :unlimited if account_has_unlimited?(account)

        plan_tier = get_plan_tier(account)
        plan_tier || :free
      end

      # Get the rate limit tier for a user
      def tier_for_user(user)
        return :free unless user

        # Check for system admin - unlimited access
        return :unlimited if user.has_permission?("system.admin")

        # Use account's tier
        tier_for_account(user.account)
      end

      # Get tier configuration
      def tier_config(tier)
        TIERS[tier.to_sym] || TIERS[:free]
      end

      # =========================================================================
      # RATE LIMIT CHECKING
      # =========================================================================

      # Check if a request should be rate limited
      def should_limit?(request, account: nil, user: nil)
        return false if rate_limiting_disabled?

        tier = determine_tier(account: account, user: user)
        return false if tier == :unlimited

        endpoint_category = categorize_endpoint(request.path, request.request_method)
        limit_key = limit_key_for_category(endpoint_category)
        period = period_for_category(endpoint_category)

        limit = get_limit(tier, limit_key)
        return false unless limit

        identifier = build_identifier(request, account, user)
        cache_key = build_cache_key(identifier, endpoint_category, period)

        current_count = increment_counter(cache_key, period)
        cost = calculate_cost(request.path, request.request_method)

        # Apply burst allowance
        effective_limit = apply_burst_allowance(limit, tier)

        current_count * cost > effective_limit
      end

      # Get remaining requests for an identifier
      def remaining_requests(request, account: nil, user: nil)
        tier = determine_tier(account: account, user: user)
        return { remaining: Float::INFINITY, limit: nil } if tier == :unlimited

        endpoint_category = categorize_endpoint(request.path, request.request_method)
        limit_key = limit_key_for_category(endpoint_category)
        period = period_for_category(endpoint_category)

        limit = get_limit(tier, limit_key)
        return { remaining: Float::INFINITY, limit: nil } unless limit

        identifier = build_identifier(request, account, user)
        cache_key = build_cache_key(identifier, endpoint_category, period)

        current_count = get_counter(cache_key)
        cost = calculate_cost(request.path, request.request_method)
        effective_limit = apply_burst_allowance(limit, tier)

        remaining = [ (effective_limit - (current_count * cost)) / cost, 0 ].max.to_i

        {
          remaining: remaining,
          limit: effective_limit.to_i,
          used: (current_count * cost).to_i,
          reset_at: get_reset_time(cache_key),
          tier: tier
        }
      end

      # =========================================================================
      # ACCOUNT-LEVEL THROTTLING
      # =========================================================================

      # Check account-level rate limit
      def account_rate_limited?(account)
        return false if rate_limiting_disabled?
        return false unless account

        tier = tier_for_account(account)
        return false if tier == :unlimited

        config = tier_config(tier)
        limit = config[:api_requests_per_hour]
        return false unless limit

        cache_key = "account_rate:#{account.id}:hourly"
        current_count = get_counter(cache_key)

        current_count >= limit
      end

      # Increment account request counter
      def track_account_request(account)
        return unless account

        cache_key = "account_rate:#{account.id}:hourly"
        increment_counter(cache_key, 1.hour)
      end

      # Get account usage stats
      def account_usage(account)
        return nil unless account

        tier = tier_for_account(account)
        config = tier_config(tier)

        hourly_key = "account_rate:#{account.id}:hourly"
        minute_key = "account_rate:#{account.id}:minute"

        {
          tier: tier,
          tier_name: config[:name],
          hourly: {
            used: get_counter(hourly_key),
            limit: config[:api_requests_per_hour],
            reset_at: get_reset_time(hourly_key)
          },
          minute: {
            used: get_counter(minute_key),
            limit: config[:api_requests_per_minute],
            reset_at: get_reset_time(minute_key)
          }
        }
      end

      # =========================================================================
      # ENDPOINT COST CALCULATION
      # =========================================================================

      # Calculate the cost of a request
      def calculate_cost(path, method)
        # Check for specific pattern matches first (most expensive)
        ENDPOINT_COSTS.each do |category, config|
          next unless config[:patterns]

          config[:patterns].each do |pattern|
            return config[:cost] if path.match?(pattern)
          end
        end

        # Fall back to method-based cost
        method = method.to_s.upcase
        case method
        when "GET", "HEAD", "OPTIONS"
          ENDPOINT_COSTS[:read][:cost]
        when "POST", "PUT", "PATCH", "DELETE"
          ENDPOINT_COSTS[:write][:cost]
        else
          1
        end
      end

      # Categorize an endpoint for rate limiting
      def categorize_endpoint(path, method)
        return :admin if path.start_with?("/api/v1/admin")
        return :webhook if path.start_with?("/api/v1/webhooks/")
        return :file if path.match?(%r{^/api/v1/files?})

        ENDPOINT_COSTS.each do |category, config|
          next unless config[:patterns]

          config[:patterns].each do |pattern|
            return category if path.match?(pattern)
          end
        end

        method.to_s.upcase == "GET" ? :read : :write
      end

      # =========================================================================
      # RATE LIMIT HEADERS
      # =========================================================================

      # Generate rate limit headers for response
      def rate_limit_headers(request, account: nil, user: nil)
        info = remaining_requests(request, account: account, user: user)

        return {} if info[:limit].nil?

        {
          "X-RateLimit-Limit" => info[:limit].to_s,
          "X-RateLimit-Remaining" => info[:remaining].to_s,
          "X-RateLimit-Reset" => info[:reset_at].to_i.to_s,
          "X-RateLimit-Tier" => info[:tier].to_s,
          "X-RateLimit-Cost" => calculate_cost(request.path, request.request_method).to_s
        }
      end

      # =========================================================================
      # ADMIN FUNCTIONS
      # =========================================================================

      # Override tier for an account (e.g., for special customers)
      def override_tier(account, tier, duration: nil)
        return false unless account && TIERS.key?(tier.to_sym)

        cache_key = "tier_override:#{account.id}"

        if duration
          Rails.cache.write(cache_key, tier.to_s, expires_in: duration)
        else
          Rails.cache.write(cache_key, tier.to_s)
        end

        true
      end

      # Clear tier override
      def clear_tier_override(account)
        return false unless account

        Rails.cache.delete("tier_override:#{account.id}")
        true
      end

      # Get all tier statistics
      def tier_statistics
        TIERS.keys.map do |tier|
          {
            tier: tier,
            name: TIERS[tier][:name],
            accounts_count: count_accounts_in_tier(tier),
            config: TIERS[tier]
          }
        end
      end

      private

      # =========================================================================
      # PRIVATE HELPERS
      # =========================================================================

      def rate_limiting_disabled?
        RateLimiting::BaseService.temporarily_disabled? ||
          ENV["DISABLE_RATE_LIMITING"] == "true"
      rescue StandardError
        false
      end

      def determine_tier(account:, user:)
        if user
          tier_for_user(user)
        elsif account
          tier_for_account(account)
        else
          :free
        end
      end

      def get_plan_tier(account)
        # Check for tier override first
        override = Rails.cache.read("tier_override:#{account.id}")
        return override.to_sym if override

        # Get from subscription plan
        plan = account.subscription&.plan
        return :free unless plan

        # Map plan name to tier
        plan_name = plan.name.to_s.downcase
        case plan_name
        when /enterprise/, /business/
          :enterprise
        when /professional/, /pro/
          :professional
        when /starter/, /basic/
          :starter
        else
          # Check plan limits for tier inference
          infer_tier_from_limits(plan.limits)
        end
      end

      def infer_tier_from_limits(limits)
        return :free unless limits.is_a?(Hash)

        # Use plan limits to infer tier
        max_users = limits["max_users"].to_i
        max_api_keys = limits["max_api_keys"].to_i

        if max_users >= 100 || max_api_keys >= 50
          :enterprise
        elsif max_users >= 25 || max_api_keys >= 20
          :professional
        elsif max_users >= 5 || max_api_keys >= 10
          :starter
        else
          :free
        end
      end

      def account_has_unlimited?(account)
        # Check for special flags
        account.settings&.dig("rate_limit_tier") == "unlimited"
      rescue StandardError
        false
      end

      def get_limit(tier, limit_key)
        config = tier_config(tier)
        config[limit_key.to_sym]
      end

      def limit_key_for_category(category)
        case category
        when :heavy
          :heavy_requests_per_hour
        when :webhook
          :webhook_requests_per_minute
        when :file
          :file_uploads_per_hour
        when :admin
          :authenticated_requests_per_hour
        else
          :api_requests_per_minute
        end
      end

      def period_for_category(category)
        case category
        when :heavy, :file, :admin
          1.hour
        when :webhook
          1.minute
        else
          1.minute
        end
      end

      def apply_burst_allowance(limit, tier)
        config = tier_config(tier)
        burst = config[:burst_allowance] || 1.0
        (limit * burst).to_i
      end

      def build_identifier(request, account, user)
        if user
          "user:#{user.id}"
        elsif account
          "account:#{account.id}"
        else
          "ip:#{request.ip}"
        end
      end

      def build_cache_key(identifier, category, period)
        period_key = period >= 1.hour ? "hourly" : "minute"
        "tiered_rate:#{identifier}:#{category}:#{period_key}"
      end

      def increment_counter(cache_key, period)
        current = Rails.cache.read(cache_key).to_i
        Rails.cache.write(cache_key, current + 1, expires_in: period)
        current + 1
      rescue StandardError
        1
      end

      def get_counter(cache_key)
        Rails.cache.read(cache_key).to_i
      rescue StandardError
        0
      end

      def get_reset_time(cache_key)
        ttl = Rails.cache.redis&.ttl(cache_key) || 0
        Time.current + ttl.seconds
      rescue StandardError
        Time.current + 1.minute
      end

      def count_accounts_in_tier(tier)
        # This is a rough estimate - actual implementation would need database query
        Account.active.count do |account|
          tier_for_account(account) == tier
        end
      rescue StandardError
        0
      end
    end
  end
end
