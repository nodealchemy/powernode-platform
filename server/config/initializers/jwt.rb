# frozen_string_literal: true

# JWT Configuration for Powernode Platform
# Supports both HMAC (HS256) and RSA (RS256) algorithms

Rails.application.configure do
  # JWT Secret Key for HMAC signing (HS256)
  config.jwt_secret_key = ENV.fetch("JWT_SECRET_KEY") do
    if Rails.env.development? || Rails.env.test?
      # Use a consistent key for development/test
      "powernode-development-jwt-secret-key-that-is-long-enough-for-security"
    else
      raise "JWT_SECRET_KEY environment variable is required in #{Rails.env}"
    end
  end

  # JWT RSA Keys for RS256 signing (production recommended)
  if Rails.env.production? || ENV["USE_RSA_JWT"] == "true"
    # RSA Private Key for signing
    config.jwt_private_key = ENV.fetch("JWT_PRIVATE_KEY") do
      if Rails.env.development? || Rails.env.test?
        # Generate development RSA key pair
        rsa_key = OpenSSL::PKey::RSA.generate(2048)
        config.jwt_public_key = rsa_key.public_key.to_pem
        rsa_key.to_pem
      else
        raise "JWT_PRIVATE_KEY environment variable is required for RSA signing"
      end
    end

    # RSA Public Key for verification
    config.jwt_public_key ||= ENV.fetch("JWT_PUBLIC_KEY") do
      if Rails.env.development? || Rails.env.test?
        # Public key will be set above when generating private key
        nil
      else
        raise "JWT_PUBLIC_KEY environment variable is required for RSA verification"
      end
    end
  end

  # JWT Algorithm preference
  config.jwt_algorithm = Rails.env.production? ? "RS256" : "HS256"

  # Token configuration
  config.jwt_token_version = 2
  config.jwt_issuer = ENV.fetch("JWT_ISSUER", "powernode-platform")
  config.jwt_audience = ENV.fetch("JWT_AUDIENCE", "powernode-api")

  # Grace period: tokens issued before this date are allowed without iss/aud claims
  # Set to deployment timestamp on first deploy with claims enforcement
  config.jwt_claims_enforcement_date = Time.parse(ENV.fetch("JWT_CLAIMS_ENFORCEMENT_DATE", "2026-02-23T00:00:00Z"))

  # Token expiration defaults (can be overridden per token type)
  config.jwt_access_token_expiration = 15.minutes
  config.jwt_refresh_token_expiration = 7.days
  config.jwt_worker_token_expiration = 30.days
  config.jwt_service_token_expiration = 1.year
  config.jwt_impersonation_token_expiration = 8.hours
  config.jwt_2fa_token_expiration = 10.minutes
  config.jwt_api_key_expiration = 1.year
end

# Validate JWT configuration on startup
Rails.application.config.after_initialize do
  # Validate HMAC key length
  secret_key = Rails.application.config.jwt_secret_key
  if secret_key.length < 32
    Rails.logger.warn "JWT secret key should be at least 32 characters long for security"
  end

  # Validate RSA keys if using RS256
  if Rails.application.config.jwt_algorithm == "RS256"
    begin
      private_key = OpenSSL::PKey::RSA.new(Rails.application.config.jwt_private_key)
      public_key = OpenSSL::PKey::RSA.new(Rails.application.config.jwt_public_key)

      # Verify key pair matches
      test_data = "jwt-key-validation-test"
      signature = private_key.sign(OpenSSL::Digest.new("SHA256"), test_data)
      unless public_key.verify(OpenSSL::Digest.new("SHA256"), signature, test_data)
        raise "JWT RSA key pair validation failed - keys do not match"
      end

      Rails.logger.info "JWT RSA key pair validated successfully"
    rescue OpenSSL::PKey::RSAError => e
      Rails.logger.error "Invalid JWT RSA keys: #{e.message}"
      raise "JWT RSA key configuration error: #{e.message}"
    end
  end

  Rails.logger.info "JWT configured with algorithm: #{Rails.application.config.jwt_algorithm}"
end
