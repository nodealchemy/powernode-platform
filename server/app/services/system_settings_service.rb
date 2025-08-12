# frozen_string_literal: true

class SystemSettingsService
  CACHE_KEY = 'system_settings'
  CACHE_EXPIRY = 1.hour

  class << self
    def get_setting(key, default_value = nil)
      settings = load_settings
      settings.dig(*key.to_s.split('.').map(&:to_sym)) || default_value
    end

    def update_settings(new_settings)
      current_settings = load_settings
      merged_settings = deep_merge(current_settings, new_settings)
      Rails.cache.write(CACHE_KEY, merged_settings, expires_in: CACHE_EXPIRY)
      merged_settings
    end

    def rate_limit_setting(type)
      # Check if rate limiting is globally disabled first
      return 0 unless rate_limiting_enabled?
      
      get_setting("rate_limiting.#{type}", default_rate_limits[type.to_sym])
    end
    
    def rate_limiting_enabled?
      # Check both environment variable and admin settings
      return false if ENV['DISABLE_RATE_LIMITING'] == 'true'
      
      get_setting('rate_limiting.enabled', true)
    end

    def clear_cache
      Rails.cache.delete(CACHE_KEY)
    end

    def load_settings
      Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_EXPIRY) do
        default_settings
      end
    end

    private

    def default_settings
      {
        maintenance_mode: false,
        registration_enabled: true,
        require_email_verification: true,
        allow_account_deletion: false,
        system_name: 'Powernode Platform',
        system_email: Rails.application.credentials.dig(:mail, :from) || 'system@powernode.local',
        support_email: Rails.application.credentials.dig(:mail, :support) || 'support@powernode.local',
        trial_period_days: 14,
        max_trial_accounts: nil,
        payment_retry_attempts: 3,
        webhook_timeout_seconds: 30,
        session_timeout_minutes: 60,
        password_min_length: 12,
        backup_retention_days: 30,
        log_retention_days: 90,
        rate_limiting: default_rate_limits,
        feature_flags: {},
        api_keys: {
          default_hourly_limit: 1000,
          default_daily_limit: 10000
        },
        smtp_settings: {
          host: Rails.application.credentials.dig(:mail, :smtp, :host),
          port: Rails.application.credentials.dig(:mail, :smtp, :port),
          use_tls: true,
          from_address: Rails.application.credentials.dig(:mail, :from)
        }
      }
    end

    def default_rate_limits
      {
        enabled: ENV['DISABLE_RATE_LIMITING'] != 'true', # Can be toggled via admin settings
        api_requests_per_minute: Rails.env.development? ? 1000 : 60,
        impersonation_attempts_per_hour: Rails.env.development? ? 50 : 5,
        login_attempts_per_hour: 10,
        password_reset_attempts_per_hour: 3,
        registration_attempts_per_hour: 5,
        email_verification_attempts_per_hour: 10,
        webhook_requests_per_minute: 100,
        authenticated_requests_per_hour: 200
      }
    end

    def deep_merge(hash1, hash2)
      hash1.merge(hash2) do |key, oldval, newval|
        if oldval.is_a?(Hash) && newval.is_a?(Hash)
          deep_merge(oldval, newval)
        else
          newval
        end
      end
    end
  end
end