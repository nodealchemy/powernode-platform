# frozen_string_literal: true

# Powernode application configuration
Rails.application.configure do
  # JWT Configuration is handled in config/initializers/jwt.rb
  # DO NOT set jwt_secret_key here - it's already configured in jwt.rb

  config.jwt_expiration_time = ENV.fetch("JWT_EXPIRATION_TIME", "24h")

  # Payment Gateway Configuration
  config.stripe_secret_key = Rails.env.production? ?
    Rails.application.credentials.stripe_secret_key :
    ENV.fetch("STRIPE_SECRET_KEY", nil)

  config.stripe_publishable_key = Rails.env.production? ?
    Rails.application.credentials.stripe_publishable_key :
    ENV.fetch("STRIPE_PUBLISHABLE_KEY", nil)

  config.stripe_webhook_secret = Rails.env.production? ?
    Rails.application.credentials.stripe_webhook_secret :
    ENV.fetch("STRIPE_WEBHOOK_SECRET", nil)

  # Frontend Configuration
  config.frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:3000")

  # Background Jobs Configuration
  config.background_jobs_api_url = ENV.fetch("BACKGROUND_JOBS_API_URL", "http://localhost:3001")
  config.background_jobs_api_token = Rails.env.production? ?
    Rails.application.credentials.background_jobs_api_token :
    ENV.fetch("BACKGROUND_JOBS_API_TOKEN", "development_service_token")

  # Worker Service Configuration
  config.worker_url = ENV.fetch("WORKER_URL", "http://localhost:4567")
  config.worker_token = Rails.env.production? ?
    Rails.application.credentials.worker_token :
    ENV.fetch("WORKER_TOKEN", "development_worker_token")

  # Legacy authentication toggle (disable to reject swt_/development_worker_token paths)
  config.legacy_auth_enabled = ENV.fetch("LEGACY_AUTH_ENABLED", "true") == "true"
end
