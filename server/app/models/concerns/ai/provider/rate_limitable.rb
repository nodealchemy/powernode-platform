# frozen_string_literal: true

module Ai
  class Provider
    module RateLimitable
      extend ActiveSupport::Concern

      included do
        # Virtual attribute for tests to set rate_limit (maps to rate_limits column)
        attr_accessor :rate_limit_override

        # Validation
        validate :rate_limit_must_be_valid
      end

      # Virtual attribute for testing request count
      def request_count_last_minute=(value)
        self.metadata = (metadata || {}).merge("request_count_last_minute" => value.to_i)
      end

      def request_count_last_minute
        metadata&.dig("request_count_last_minute") || 0
      end

      def request_count_last_hour
        metadata&.dig("request_count_last_hour") || 0
      end

      def rate_limit
        @rate_limit_override || rate_limits.presence || { "requests_per_minute" => 60, "tokens_per_minute" => 10000 }
      end

      def rate_limit=(value)
        @rate_limit_override = value
        # Also update the rate_limits column if it's a hash
        self.rate_limits = value if value.is_a?(Hash)
      end

      def rate_limit_for_account(account)
        # Return account-specific rate limits or default provider limits
        credential = credentials.find_by(account: account, is_active: true)
        return credential.rate_limits if credential&.rate_limits&.any?

        rate_limits
      end

      def rate_limit_remaining(limit_type = :requests_per_minute)
        return nil unless rate_limits.any?

        limit_key = limit_type.to_s
        rate_limit_value = rate_limits[limit_key]
        return nil unless rate_limit_value

        # Map limit type to usage metadata key
        usage_key = case limit_type.to_sym
                    when :requests_per_minute
                      "request_count_last_minute"
                    when :tokens_per_minute
                      "token_count_last_minute"
                    else
                      "#{limit_key}_usage"
                    end

        current_usage = metadata&.dig(usage_key) || 0
        [rate_limit_value - current_usage, 0].max
      end

      def can_make_request?
        return true unless rate_limits.any?

        requests_per_minute = rate_limits["requests_per_minute"]
        return true unless requests_per_minute

        (metadata&.dig("request_count_last_minute") || 0) < requests_per_minute
      end

      private

      def update_rate_limit_counters(requests, timestamp)
        current_metadata = metadata || {}
        update_rate_limit_counters_in_metadata(current_metadata, requests, timestamp)
        self.metadata = current_metadata
      end

      def update_rate_limit_counters_in_metadata(metadata_hash, requests, timestamp)
        # Update per-minute counter
        minute_key = timestamp.strftime("%Y-%m-%d-%H-%M")
        if metadata_hash.dig("rate_limit_window") != minute_key
          metadata_hash["rate_limit_window"] = minute_key
          metadata_hash["request_count_last_minute"] = requests
        else
          metadata_hash["request_count_last_minute"] = (metadata_hash["request_count_last_minute"] || 0) + requests
        end

        # Update per-hour counter
        hour_key = timestamp.strftime("%Y-%m-%d-%H")
        if metadata_hash.dig("rate_limit_hour_window") != hour_key
          metadata_hash["rate_limit_hour_window"] = hour_key
          metadata_hash["request_count_last_hour"] = requests
        else
          metadata_hash["request_count_last_hour"] = (metadata_hash["request_count_last_hour"] || 0) + requests
        end
      end

      def rate_limit_must_be_valid
        # Check the virtual attribute or the rate_limits column
        limit_config = @rate_limit_override || rate_limits
        return if limit_config.blank? || !limit_config.is_a?(Hash)

        limit_config.each do |key, value|
          case key.to_s
          when "requests_per_minute", "requests_per_hour", "requests_per_day",
               "tokens_per_minute", "tokens_per_hour", "tokens_per_day"
            unless value.is_a?(Integer) && value > 0
              errors.add(:rate_limit, "#{key} must be a positive integer")
            end
          end
        end
      end
    end
  end
end
