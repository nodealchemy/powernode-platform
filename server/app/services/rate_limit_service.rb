# frozen_string_literal: true

class RateLimitService
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

    # Clear rate limits for a specific IP or user
    def clear_limits_for(identifier)
      pattern = case identifier
      when /\A\d+\z/ # User ID
                 "rate_limit:*:*:user_#{identifier}"
      when /\A\d+\.\d+\.\d+\.\d+\z/ # IP address
                 "rate_limit:*:*:ip_#{identifier}"
      else
                 raise ArgumentError, "Invalid identifier: #{identifier}"
      end

      keys_cleared = 0
      Rails.cache.redis.keys(pattern).each do |key|
        Rails.cache.delete(key)
        keys_cleared += 1
      end

      keys_cleared
    end

    # Check if an identifier is currently rate limited
    def rate_limited?(identifier)
      pattern = case identifier
      when /\A\d+\z/ # User ID
                 "rate_limit:*:*:user_#{identifier}"
      when /\A\d+\.\d+\.\d+\.\d+\z/ # IP address
                 "rate_limit:*:*:ip_#{identifier}"
      else
                 return false
      end

      Rails.cache.redis.keys(pattern).any? do |key|
        current_count = Rails.cache.read(key) || 0
        limit = extract_limit_from_key(key)
        current_count >= limit if limit
      end
    end

    # Get detailed rate limit info for an identifier
    def get_limit_info(identifier)
      pattern = case identifier
      when /\A\d+\z/ # User ID
                 "rate_limit:*:*:user_#{identifier}"
      when /\A\d+\.\d+\.\d+\.\d+\z/ # IP address
                 "rate_limit:*:*:ip_#{identifier}"
      else
                 return {}
      end

      limits = {}
      Rails.cache.redis.keys(pattern).each do |key|
        parts = key.split(":")
        next if parts.length < 4

        controller = parts[1]
        action = parts[2]
        current_count = Rails.cache.read(key) || 0
        limit = extract_limit_from_key(key)
        ttl = Rails.cache.redis.ttl(key)

        limits["#{controller}##{action}"] = {
          current: current_count,
          limit: limit,
          remaining: [ limit - current_count, 0 ].max,
          reset_in: ttl > 0 ? ttl : 0
        } if limit
      end

      limits
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

    def count_current_violations
      violations = 0
      Rails.cache.redis.keys("rate_limit:*").each do |key|
        current_count = Rails.cache.read(key) || 0
        limit = extract_limit_from_key(key)
        violations += 1 if limit && current_count >= limit
      end
      violations
    rescue StandardError => e
      Rails.logger.error "Error counting rate limit violations: #{e.message}"
      0
    end

    def count_active_limits
      Rails.cache.redis.keys("rate_limit:*").count
    rescue StandardError => e
      Rails.logger.error "Error counting active limits: #{e.message}"
      0
    end

    def get_current_configuration
      rate_limit_keys = %w[
        api_requests_per_minute login_attempts_per_hour registration_attempts_per_hour
        password_reset_attempts_per_hour email_verification_attempts_per_hour
        authenticated_requests_per_hour impersonation_attempts_per_hour
        webhook_requests_per_minute websocket_connections_per_minute
      ]
      limits = rate_limit_keys.each_with_object({}) do |key, hash|
        hash[key.to_sym] = AdminSetting.find_by(key: key)&.value&.to_i
      end

      {
        enabled: ENV["DISABLE_RATE_LIMITING"] != "true",
        limits: limits
      }
    end

    def extract_limit_from_key(key)
      parts = key.split(":")
      return nil if parts.length < 4

      controller_name = parts[1]
      limit_type = determine_limit_type_for_controller(controller_name)
      AdminSetting.find_by(key: limit_type)&.value&.to_i
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
