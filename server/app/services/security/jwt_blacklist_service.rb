# frozen_string_literal: true

module Security
  # JWT Token Blacklist Service
  # Handles blacklisting and validation of JWT tokens using Redis for performance
  # Falls back to database storage when Redis is unavailable
  class Security::JwtBlacklistService
    REDIS_KEY_PREFIX = "jwt_blacklist:"
    CLEANUP_BATCH_SIZE = 1000
    # How long a user-level blacklist marker stays in force. Tokens issued before
    # the marker was (re)written are revoked for this window.
    USER_BLACKLIST_TTL = 1.year

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
      rescue StandardError => e
        Rails.logger.error "Failed to blacklist JWT token #{jti}: #{e.message}"
        false
      end

      # Check if a JWT token is blacklisted.
      #
      # Pass the token's `user_id` (sub) and `issued_at` (iat) so the check also
      # honors a user-level blacklist (see blacklist_user_tokens): every token the
      # user held that was issued BEFORE their tokens were blacklisted is treated
      # as revoked, while tokens issued afterwards (e.g. a fresh login) stay valid.
      # Without that context only the per-jti entry is consulted.
      def blacklisted?(jti, user_id: nil, issued_at: nil)
        return false unless jti.present?

        if redis_available?
          return true if blacklisted_in_redis?(jti)

          user_tokens_revoked_redis?(user_id, issued_at)
        else
          return true if blacklisted_in_database?(jti)

          user_tokens_revoked_database?(user_id, issued_at)
        end
      rescue StandardError => e
        Rails.logger.error "Error checking JWT blacklist for #{jti}: #{e.message}"
        # Fail closed: a revocation check that cannot positively confirm the token
        # is NOT blacklisted must DENY it. Returning false here would let a revoked
        # token through whenever the backing store is unreachable (auth bypass).
        true
      end

      # Blacklist all tokens for a user (e.g., on account suspension)
      def blacklist_user_tokens(user_id, reason: "account_suspended")
        if redis_available?
          blacklist_user_tokens_redis(user_id, reason)
        else
          blacklist_user_tokens_database(user_id, reason)
        end

        Rails.logger.info "All JWT tokens blacklisted for user #{user_id} (reason: #{reason})"
      rescue StandardError => e
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
      rescue StandardError => e
        Rails.logger.error "Failed to cleanup expired JWT blacklist entries: #{e.message}"
      end

      # Get blacklist statistics
      def statistics
        if redis_available?
          statistics_redis
        else
          statistics_database
        end
      rescue StandardError => e
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
        @redis ||= Powernode::Redis.client
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
        redis.exists?(key)
      end

      def blacklist_user_tokens_redis(user_id, reason)
        # Set a user-level blacklist marker. `blacklisted_at` is the cutoff: tokens
        # issued before it are revoked. setex overwrites on re-blacklist, so the
        # cutoff always reflects the most recent event.
        user_key = "#{REDIS_KEY_PREFIX}user:#{user_id}"
        value = {
          reason: reason,
          blacklisted_at: Time.current.iso8601,
          expires_at: USER_BLACKLIST_TTL.from_now.iso8601
        }.to_json

        redis.setex(user_key, USER_BLACKLIST_TTL.to_i, value)
      end

      def cleanup_expired_redis
        # Redis automatically expires keys, but we can scan for cleanup
        keys = redis.scan_each(match: "#{REDIS_KEY_PREFIX}*").to_a
        cleaned = 0

        keys.each_slice(CLEANUP_BATCH_SIZE) do |batch|
          # redis-rb 5.x `exists?` returns a Boolean, so a key that scan_each
          # enumerated but that now reports false has been auto-expired by Redis.
          cleaned += batch.count { |key| !redis.exists?(key) }
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

      # User-level blacklist (redis): an active marker key revokes every token the
      # user held that was issued before its `blacklisted_at` cutoff.
      def user_tokens_revoked_redis?(user_id, issued_at)
        return false if user_id.blank?

        raw = redis.get("#{REDIS_KEY_PREFIX}user:#{user_id}")
        return false if raw.blank?

        token_predates_cutoff?(issued_at, extract_blacklisted_at(raw))
      end

      # User-level blacklist (database): the active marker row's cutoff is its
      # `updated_at` — the exact instant of the most recent (re)blacklist, which
      # save! stamps on every upsert. (Reconstructing it from expires_at would be
      # skewed by calendar-aware `1.year` math, which does not round-trip.)
      def user_tokens_revoked_database?(user_id, issued_at)
        return false if user_id.blank?
        return false unless defined?(JwtBlacklist)

        marker = JwtBlacklist.where(jti: "user_blacklist_#{user_id}", user_blacklist: true)
                             .where("expires_at > ?", Time.current)
                             .first
        return false unless marker

        token_predates_cutoff?(issued_at, marker.updated_at)
      end

      # A user marker is present; decide whether THIS token predates the cutoff.
      # An unparseable cutoff or a missing issued_at means we cannot prove the
      # token was issued after the user was blacklisted, so we revoke (fail safe).
      def token_predates_cutoff?(issued_at, cutoff)
        return true if cutoff.nil?
        return true if issued_at.blank?

        issued_at.to_i < cutoff.to_i
      end

      def extract_blacklisted_at(raw)
        ts = JSON.parse(raw)["blacklisted_at"]
        ts.present? ? Time.iso8601(ts) : nil
      rescue JSON::ParserError, ArgumentError
        nil
      end

      def blacklist_user_tokens_database(user_id, reason)
        return unless defined?(JwtBlacklist)

        # Upsert the per-user marker so re-blacklisting refreshes the cutoff
        # (expires_at) instead of being swallowed as a duplicate jti.
        marker = JwtBlacklist.find_or_initialize_by(jti: "user_blacklist_#{user_id}")
        marker.assign_attributes(
          reason: reason,
          user_id: user_id,
          user_blacklist: true,
          expires_at: USER_BLACKLIST_TTL.from_now
        )
        marker.save!
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
