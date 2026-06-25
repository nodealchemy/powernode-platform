# frozen_string_literal: true

module Security
  class JwtService
    # Token types supported by the system
    TOKEN_TYPES = %w[access refresh worker impersonation api_key 2fa].freeze

    # Default expiration times for different token types
    EXPIRATION_TIMES = {
      access: 15.minutes,
      refresh: 7.days,
      worker: 30.days,
      impersonation: 8.hours,
      api_key: 1.year,
      "2fa" => 10.minutes
    }.freeze

    # Current token version for migration support
    CURRENT_TOKEN_VERSION = 2

    class << self
      # Enhanced encode method with token type support
      def encode(payload, exp = nil, algorithm: nil)
        # Set default expiration based on token type
        token_type = payload[:type] || payload["type"] || "access"
        exp ||= EXPIRATION_TIMES[token_type.to_sym]&.from_now || 24.hours.from_now

        # Ensure required claims are present
        enhanced_payload = {
          **payload.with_indifferent_access,
          type: token_type,
          exp: exp.to_i,
          iat: Time.current.to_i,
          jti: SecureRandom.hex(16), # Unique token identifier
          version: CURRENT_TOKEN_VERSION,
          iss: Rails.application.config.jwt_issuer,
          aud: Rails.application.config.jwt_audience
        }

        # Use appropriate algorithm
        algorithm ||= default_algorithm
        JWT.encode(enhanced_payload, signing_key(algorithm), algorithm)
      end

      # Enhanced decode method with blacklist checking and secret rotation support
      def decode(token, algorithm: nil)
        algorithm ||= default_algorithm

        decode_options = {
          algorithm: algorithm,
          verify_iss: true,
          iss: Rails.application.config.jwt_issuer,
          verify_aud: true,
          aud: Rails.application.config.jwt_audience
        }

        # Try decoding with current secret
        begin
          decoded = JWT.decode(token, verification_key(algorithm), true, decode_options)[0]
          payload = HashWithIndifferentAccess.new(decoded)
        rescue JWT::VerificationError => e
          # Active key failed to verify — retry against the rotation grace key(s).
          # (Replaces the prior dead ternary that fed the HMAC old_secret to an
          # RS256 verify.)
          decoded = decode_with_grace_keys(token, decode_options, algorithm)
          raise StandardError, "Invalid token: #{e.message}" unless decoded

          payload = HashWithIndifferentAccess.new(decoded)
          Rails.logger.info "Token verified with a rotation grace key (#{algorithm})"
        rescue JWT::InvalidIssuerError, JWT::InvalidAudError => e
          # Grace period for tokens issued before claims enforcement
          # Allow tokens without iss/aud for 7 days after deployment
          begin
            # Decode without iss/aud verification to check iat
            raw_decoded = JWT.decode(token, verification_key(algorithm), true, {
              algorithm: algorithm,
              verify_iss: false,
              verify_aud: false
            })[0]
            raw_payload = HashWithIndifferentAccess.new(raw_decoded)

            # Check if token was issued before claims enforcement
            grace_cutoff = (Rails.application.config.jwt_claims_enforcement_date || Time.current).to_i
            if raw_payload[:iat] && raw_payload[:iat] < grace_cutoff
              Rails.logger.warn "JWT grace period: allowing token without iss/aud claims (issued: #{Time.at(raw_payload[:iat])})"

              # Check blacklist (jti-level and user-level via sub/iat)
              jti = raw_payload[:jti]
              if jti && JwtBlacklistService.blacklisted?(jti, user_id: raw_payload[:sub] || raw_payload[:user_id], issued_at: raw_payload[:iat])
                raise StandardError, "Invalid token: Token has been blacklisted"
              end

              raw_payload
            else
              raise StandardError, "Invalid token: #{e.message}"
            end
          rescue JWT::DecodeError
            raise StandardError, "Invalid token: #{e.message}"
          end
        end

        # Check if token is blacklisted (jti-level and user-level via sub/iat)
        jti = payload[:jti]
        if jti && JwtBlacklistService.blacklisted?(jti, user_id: payload[:sub] || payload[:user_id], issued_at: payload[:iat])
          raise StandardError, "Invalid token: Token has been blacklisted"
        end

        payload
      rescue JWT::DecodeError, JWT::ExpiredSignature => e
        raise StandardError, "Invalid token: #{e.message}"
      end

      # Generate comprehensive user token set with permissions
      def generate_user_tokens(user, metadata: {})
        # Build comprehensive user payload
        user_payload = build_user_payload(user, metadata)

        access_payload = user_payload.merge(type: "access")
        refresh_payload = {
          sub: user.id,
          account_id: user.account_id,
          type: "refresh",
          version: CURRENT_TOKEN_VERSION
        }.merge(metadata.slice(:ip, :device_id))

        {
          access_token: encode(access_payload),
          refresh_token: encode(refresh_payload),
          expires_at: EXPIRATION_TIMES[:access].from_now,
          refresh_expires_at: EXPIRATION_TIMES[:refresh].from_now
        }
      end

      # Generate worker tokens with permissions
      def generate_worker_tokens(worker, metadata: {})
        worker_payload = build_worker_payload(worker, metadata)

        {
          access_token: encode(worker_payload.merge(type: "worker")),
          expires_at: EXPIRATION_TIMES[:worker].from_now
        }
      end

      # Refresh access token using refresh token
      def refresh_access_token(refresh_token)
        payload = decode(refresh_token)

        raise StandardError, "Invalid token type" unless payload[:type] == "refresh"
        validate_token_version(payload)

        # Find user by subject claim
        user = User.find(payload[:sub] || payload[:user_id])
        raise StandardError, "User not found or inactive" unless user&.active?

        # Check if user permissions have changed
        metadata = extract_metadata(payload)
        if permissions_changed?(user, payload)
          # Force full re-authentication if permissions changed significantly
          blacklist_token(refresh_token)
          raise StandardError, "Permissions changed - please log in again"
        end

        generate_user_tokens(user, metadata: metadata)
      rescue ActiveRecord::RecordNotFound
        raise StandardError, "User not found"
      end

      # Generate 2FA verification token
      def generate_2fa_token(user, metadata: {})
        # Generate a partial authentication token that requires 2FA verification
        payload = {
          sub: user.id,
          account_id: user.account_id,
          email: user.email,
          type: "2fa",
          requires_2fa: true,
          version: CURRENT_TOKEN_VERSION
        }.merge(metadata.slice(:ip, :device_id))

        {
          token: encode(payload),
          expires_at: EXPIRATION_TIMES["2fa"].from_now
        }
      end

      # Verify 2FA token and generate full tokens
      def verify_2fa_token(token, two_factor_code)
        payload = decode(token)

        raise StandardError, "Invalid token type" unless payload[:type] == "2fa"
        raise StandardError, "Token does not require 2FA" unless payload[:requires_2fa]
        validate_token_version(payload)

        user = User.find(payload[:sub] || payload[:user_id])
        raise StandardError, "User not found or inactive" unless user&.active?

        unless user.verify_two_factor_token(two_factor_code)
          raise StandardError, "Invalid 2FA code"
        end

        # Blacklist the 2FA token to prevent reuse
        blacklist_token(token)

        # Extract metadata for new tokens
        metadata = extract_metadata(payload)

        # Generate full access tokens after successful 2FA verification
        generate_user_tokens(user, metadata: metadata)
      rescue ActiveRecord::RecordNotFound
        raise StandardError, "User not found"
      end

      # Blacklist token using blacklist service
      def blacklist_token(token, reason: "logout", user_id: nil)
        begin
          # Decode token to get JTI and expiration without blacklist check
          algorithm = default_algorithm
          decoded = JWT.decode(token, verification_key(algorithm), true, { algorithm: algorithm })[0]
          jti = decoded["jti"]
          expires_at = Time.at(decoded["exp"])
          user_id ||= decoded["sub"] || decoded["user_id"]

          return true unless jti # Can't blacklist tokens without JTI

          # Use the centralized blacklist service
          JwtBlacklistService.blacklist(jti, expires_at, reason: reason, user_id: user_id)
        rescue JWT::DecodeError, JWT::ExpiredSignature
          # If token is invalid or expired, we don't need to blacklist it
          true
        rescue StandardError => e
          Rails.logger.error "Failed to blacklist token: #{e.message}"
          false
        end
      end

      # Check if token is blacklisted
      def blacklisted?(token)
        begin
          algorithm = default_algorithm
          decoded = JWT.decode(token, verification_key(algorithm), false)[0] # Don't verify for blacklist check
          jti = decoded["jti"]

          return false unless jti

          JwtBlacklistService.blacklisted?(jti, user_id: decoded["sub"] || decoded["user_id"], issued_at: decoded["iat"])
        rescue JWT::DecodeError
          false # Invalid tokens are not "blacklisted", they're just invalid
        end
      end

      # Blacklist all tokens for a user
      def blacklist_user_tokens(user_id, reason: "logout")
        JwtBlacklistService.blacklist_user_tokens(user_id, reason: reason)
      end

      private

      # Build user payload without permissions (permissions queried separately)
      def build_user_payload(user, metadata = {})
        {
          sub: user.id,
          account_id: user.account_id,
          email: user.email,
          permission_version: calculate_permission_version(user),
          version: CURRENT_TOKEN_VERSION
        }.merge(metadata.slice(:ip, :device_id, :user_agent))
      end

      # Build worker payload without permissions (permissions queried separately)
      def build_worker_payload(worker, metadata = {})
        {
          sub: worker.id,
          worker_type: worker.system? ? "system" : "account",
          account_id: worker.account_id,
          name: worker.name,
          permission_version: calculate_worker_permission_version(worker),
          version: CURRENT_TOKEN_VERSION
        }.merge(metadata.slice(:ip, :user_agent))
      end

      # Extract metadata from token payload
      def extract_metadata(payload)
        payload.slice(:ip, :device_id, :user_agent).compact
      end

      # Check if user permissions have changed since token was issued
      def permissions_changed?(user, payload)
        return false unless payload[:permission_version]

        current_version = calculate_permission_version(user)
        payload[:permission_version] != current_version
      end

      # Calculate permission version hash for user
      def calculate_permission_version(user)
        permissions_string = user.permission_names.sort.join(",")
        Digest::SHA256.hexdigest(permissions_string)[0..7]
      end

      # Calculate permission version hash for worker
      def calculate_worker_permission_version(worker)
        permissions_string = worker.permission_names.sort.join(",")
        Digest::SHA256.hexdigest(permissions_string)[0..7]
      end

      # Validate token version
      def validate_token_version(payload)
        version = payload[:version] || payload["version"] || 1
        unless version >= 1 && version <= CURRENT_TOKEN_VERSION
          raise StandardError, "Unsupported token version: #{version}"
        end
      end

      # Get default signing algorithm
      def default_algorithm
        Rails.application.config.jwt_algorithm
      end

      # Get signing key based on algorithm
      def signing_key(algorithm)
        case algorithm
        when "HS256"
          secret_key
        when "RS256"
          private_key
        else
          raise StandardError, "Unsupported algorithm: #{algorithm}"
        end
      end

      # Get verification key based on algorithm
      def verification_key(algorithm)
        case algorithm
        when "HS256"
          secret_key
        when "RS256"
          public_key
        else
          raise StandardError, "Unsupported algorithm: #{algorithm}"
        end
      end

      # HMAC secret (dev/test). Read LIVE from config — not memoized — so an HS256
      # rotation that reassigns config.jwt_secret_key takes effect immediately for
      # newly-signed tokens (a memo here silently kept signing with the old secret).
      def secret_key
        Rails.application.config.jwt_secret_key
      end

      # Active RSA private key for signing — sourced from JwtKeyStore (store-backed,
      # rotation-aware, ENV fail-safe fallback). Memoized by PEM: the parsed key is
      # reused until the PEM actually changes (after a rotation propagates), so a
      # rotation takes effect within the store's cache TTL with no per-call parse
      # and no process restart.
      def private_key
        pem = Security::JwtKeyStore.active_private_key_pem
        if pem != @private_key_pem
          key = OpenSSL::PKey::RSA.new(pem)
          @private_key = key
          @private_key_pem = pem # gate set LAST: readers never see a new PEM with a stale key
        end
        @private_key
      end

      # Active RSA public key for verification (store-backed; ENV fallback). Same
      # PEM-gated memoization as #private_key.
      def public_key
        pem = Security::JwtKeyStore.active_public_key_pem
        if pem != @public_key_pem
          key = OpenSSL::PKey::RSA.new(pem)
          @public_key = key
          @public_key_pem = pem # gate set LAST: readers never see a new PEM with a stale key
        end
        @public_key
      end

      # Attempt to decode TOKEN with the rotation grace key(s) after the active key
      # failed. Returns the decoded payload hash, or nil if none verify.
      # RS256: try the freshly-refreshed active key (so a worker lagging a rotation
      # accepts new-key tokens) plus every retired public key still inside its
      # grace window (multi-generation — overlapping rotations all keep verifying).
      # HS256 (dev/test): the old HMAC secret from the rotation cache.
      def decode_with_grace_keys(token, decode_options, algorithm)
        case algorithm
        when "RS256"
          grace_rsa_keys(Security::JwtKeyStore.grace_verification_pems).each do |key|
            return JWT.decode(token, key, true, decode_options)[0]
          rescue JWT::DecodeError
            next
          end
          nil
        when "HS256"
          data = Rails.cache.read("jwt_secret_rotation")
          return nil unless data && data[:grace_period_ends_at] && Time.current < data[:grace_period_ends_at]

          begin
            JWT.decode(token, data[:old_secret], true, decode_options)[0]
          rescue JWT::DecodeError
            nil
          end
        end
      end

      # Parse grace-candidate PEMs into RSA keys, reusing previously-parsed objects
      # (keyed by PEM) and pruning any no longer in the candidate set — so a flood
      # of invalid tokens can't re-parse the same keys on every verification miss.
      def grace_rsa_keys(pems)
        @grace_key_cache ||= {}
        @grace_key_cache.select! { |pem, _| pems.include?(pem) }
        pems.filter_map do |pem|
          @grace_key_cache[pem] ||=
            begin
              OpenSSL::PKey::RSA.new(pem)
            rescue OpenSSL::PKey::RSAError
              nil
            end
        end
      end
    end
  end
end
