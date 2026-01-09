# frozen_string_literal: true

module Security
  # JWT Token Blacklist Service
  # Handles blacklisting and validation of JWT tokens using Redis for performance
  # Falls back to database storage when Redis is unavailable
  class Security::JwtBlacklistService
    REDIS_KEY_PREFIX = "jwt_blacklist:"
    CLEANUP_BATCH_SIZE = 1000

    class << self
      # Blacklist a JWT token by its JTI
      def blacklist(jti, expires_at, reason: "logout", user_id: nil)
        return false unless jti.present?

        ttl = calculate_ttl(expires_at)
        return true if ttl <= 0 # Already expired

        if redis_available?
          blacklist_in_redis(jti, ttl, reason, user_id)
        else
          blacklist_in_database(jti, expires_at, reason, user_id)
        end

        # Log blacklist action
        Rails.logger.info "JWT token blacklisted: #{jti[0..7]}... (reason: #{reason})"
        true
      rescue => e
        Rails.logger.error "Failed to blacklist JWT token #{jti}: #{e.message}"
        false
      end

      # Check if a JWT token is blacklisted
      def blacklisted?(jti)
        return false unless jti.present?

        if redis_available?
          blacklisted_in_redis?(jti)
        else
          blacklisted_in_database?(jti)
        end
      rescue => e
        Rails.logger.error "Error checking JWT blacklist for #{jti}: #{e.message}"
        # Fail open - if we can't check blacklist, allow the token
        false
      end

      # Blacklist all tokens for a user (e.g., on account suspension)
      def blacklist_user_tokens(user_id, reason: "account_suspended")
        if redis_available?
          blacklist_user_tokens_redis(user_id, reason)
        else
          blacklist_user_tokens_database(user_id, reason)
        end

        Rails.logger.info "All JWT tokens blacklisted for user #{user_id} (reason: #{reason})"
      rescue => e
        Rails.logger.error "Failed to blacklist user tokens for #{user_id}: #{e.message}"
        false
      end

      # Clean up expired blacklisted tokens
      def cleanup_expired
        if redis_available?
          cleanup_expired_redis
        else
          cleanup_expired_database
        end
      rescue => e
        Rails.logger.error "Failed to cleanup expired JWT blacklist entries: #{e.message}"
      end

      # Get blacklist statistics
      def statistics
        if redis_available?
          statistics_redis
        else
          statistics_database
        end
      rescue => e
        Rails.logger.error "Failed to get JWT blacklist statistics: #{e.message}"
        { total: 0, error: e.message }
      end

      private

      # Check if Redis is available
      def redis_available?
        defined?(Redis) && Rails.cache.is_a?(ActiveSupport::Cache::RedisCacheStore)
      end

      # Get Redis connection
      def redis
        @redis ||= if defined?(Redis) && ENV["REDIS_URL"]
                     Redis.new(url: ENV["REDIS_URL"])
        else
                     Rails.cache.redis
        end
      end

      # Calculate TTL in seconds
      def calculate_ttl(expires_at)
        (expires_at.to_time - Time.current).to_i
      end

      # Redis-based blacklist methods
      def blacklist_in_redis(jti, ttl, reason, user_id)
        key = "#{REDIS_KEY_PREFIX}#{jti}"
        value = {
          reason: reason,
          user_id: user_id,
          blacklisted_at: Time.current.iso8601
        }.to_json

        redis.setex(key, ttl, value)
      end

      def blacklisted_in_redis?(jti)
        key = "#{REDIS_KEY_PREFIX}#{jti}"
        redis.exists?(key) > 0
      end

      def blacklist_user_tokens_redis(user_id, reason)
        # Set a user-level blacklist flag
        user_key = "#{REDIS_KEY_PREFIX}user:#{user_id}"
        value = {
          reason: reason,
          blacklisted_at: Time.current.iso8601,
          expires_at: (Time.current + 1.year).iso8601 # Long TTL for user blacklist
        }.to_json

        redis.setex(user_key, 1.year.to_i, value)
      end

      def cleanup_expired_redis
        # Redis automatically expires keys, but we can scan for cleanup
        keys = redis.scan_each(match: "#{REDIS_KEY_PREFIX}*").to_a
        cleaned = 0

        keys.each_slice(CLEANUP_BATCH_SIZE) do |batch|
          # Redis handles expiration automatically, just count existing keys
          cleaned += batch.count { |key| redis.exists?(key) == 0 }
        end

        Rails.logger.info "Redis JWT blacklist cleanup: #{cleaned} expired entries found"
        cleaned
      end

      def statistics_redis
        keys = redis.scan_each(match: "#{REDIS_KEY_PREFIX}*").to_a
        user_keys = keys.select { |k| k.include?(":user:") }
        token_keys = keys - user_keys

        {
          total: keys.size,
          user_blacklists: user_keys.size,
          token_blacklists: token_keys.size,
          storage: "redis"
        }
      end

      # Database fallback methods (requires migration for JwtBlacklist model)
      def blacklist_in_database(jti, expires_at, reason, user_id)
        # Create JwtBlacklist model if it doesn't exist
        ensure_blacklist_model

        JwtBlacklist.create!(
          jti: jti,
          expires_at: expires_at,
          reason: reason,
          user_id: user_id
        )
      rescue ActiveRecord::RecordInvalid
        # Already exists, which is fine
        true
      end

      def blacklisted_in_database?(jti)
        return false unless defined?(JwtBlacklist)

        JwtBlacklist.where(jti: jti).where("expires_at > ?", Time.current).exists?
      end

      def blacklist_user_tokens_database(user_id, reason)
        return unless defined?(JwtBlacklist)

        # Mark user as having all tokens blacklisted
        expires_at = 1.year.from_now
        JwtBlacklist.create!(
          jti: "user_blacklist_#{user_id}",
          expires_at: expires_at,
          reason: reason,
          user_id: user_id,
          user_blacklist: true
        )
      rescue ActiveRecord::RecordInvalid
        # Already exists
        true
      end

      def cleanup_expired_database
        return 0 unless defined?(JwtBlacklist)

        deleted = JwtBlacklist.where("expires_at <= ?", Time.current).delete_all
        Rails.logger.info "Database JWT blacklist cleanup: #{deleted} expired entries removed"
        deleted
      end

      def statistics_database
        return { total: 0, storage: "none" } unless defined?(JwtBlacklist)

        total = JwtBlacklist.where("expires_at > ?", Time.current).count
        user_blacklists = JwtBlacklist.where("expires_at > ?", Time.current)
                                     .where(user_blacklist: true).count

        {
          total: total,
          user_blacklists: user_blacklists,
          token_blacklists: total - user_blacklists,
          storage: "database"
        }
      end

      # Ensure JwtBlacklist model exists (create if needed)
      def ensure_blacklist_model
        return if defined?(JwtBlacklist)

        # Create the model dynamically if it doesn't exist
        Object.const_set(:JwtBlacklist, Class.new(ApplicationRecord) do
          self.table_name = "jwt_blacklists"

          validates :jti, presence: true, uniqueness: true
          validates :expires_at, presence: true

          scope :active, -> { where("expires_at > ?", Time.current) }
          scope :expired, -> { where("expires_at <= ?", Time.current) }
          scope :user_blacklists, -> { where(user_blacklist: true) }

          def self.blacklisted?(jti)
            active.exists?(jti: jti)
          end
        end)
      end
    end
  end
end
