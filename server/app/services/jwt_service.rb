# frozen_string_literal: true

class JwtService
  class << self
    def encode(payload, exp = 24.hours.from_now)
      payload[:exp] = exp.to_i
      JWT.encode(payload, secret_key, "HS256")
    end

    def decode(token)
      # Check if token is blacklisted
      raise StandardError, "Invalid token: Token has been blacklisted" if BlacklistedToken.blacklisted?(token)

      decoded = JWT.decode(token, secret_key, true, { algorithm: "HS256" })[0]
      HashWithIndifferentAccess.new(decoded)
    rescue JWT::DecodeError, JWT::ExpiredSignature => e
      raise StandardError, "Invalid token: #{e.message}"
    end

    def generate_tokens(user)
      access_payload = {
        user_id: user.id,
        account_id: user.account_id,
        email: user.email,
        role: user.role || 'member',
        type: "access"
      }

      refresh_payload = {
        user_id: user.id,
        account_id: user.account_id,
        type: "refresh",
        jti: SecureRandom.hex(8) # Unique token identifier
      }

      {
        access_token: encode(access_payload, 15.minutes.from_now),
        refresh_token: encode(refresh_payload, 7.days.from_now),
        expires_at: 15.minutes.from_now
      }
    end

    def refresh_access_token(refresh_token)
      payload = decode(refresh_token)

      raise StandardError, "Invalid token type" unless payload[:type] == "refresh"

      user = User.find(payload[:user_id])
      raise StandardError, "User not found or inactive" unless user&.active?

      generate_tokens(user)
    rescue ActiveRecord::RecordNotFound
      raise StandardError, "User not found"
    end

    def generate_2fa_token(user)
      # Generate a partial authentication token that requires 2FA verification
      payload = {
        user_id: user.id,
        account_id: user.account_id,
        email: user.email,
        role: user.role || 'member',
        type: "2fa_required",
        requires_2fa: true
      }

      {
        token: encode(payload, 10.minutes.from_now),
        expires_at: 10.minutes.from_now
      }
    end

    def verify_2fa_token(token, two_factor_code)
      payload = decode(token)

      raise StandardError, "Invalid token type" unless payload[:type] == "2fa_required"
      raise StandardError, "Token does not require 2FA" unless payload[:requires_2fa]

      user = User.find(payload[:user_id])
      raise StandardError, "User not found or inactive" unless user&.active?
      
      unless user.verify_two_factor_token(two_factor_code)
        raise StandardError, "Invalid 2FA code"
      end

      # Generate full access tokens after successful 2FA verification
      generate_tokens(user)
    rescue ActiveRecord::RecordNotFound
      raise StandardError, "User not found"
    end

    def blacklist_token(token, user, reason: "logout")
      # Decode token to get expiration time without using our own decode method (to avoid blacklist check)
      begin
        decoded = JWT.decode(token, secret_key, true, { algorithm: "HS256" })[0]
        expires_at = Time.at(decoded["exp"])

        BlacklistedToken.create!(
          token: token,
          user: user,
          expires_at: expires_at,
          reason: reason
        )
        true
      rescue JWT::DecodeError, JWT::ExpiredSignature
        # If token is invalid or expired, we don't need to blacklist it
        true
      rescue => e
        Rails.logger.error "Failed to blacklist token: #{e.message}"
        false
      end
    end

    private

    def secret_key
      @secret_key ||= Rails.application.config.jwt_secret_key
    end
  end
end
