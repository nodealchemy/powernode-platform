# frozen_string_literal: true

# Stripe configuration — only when business extension provides the gem
Rails.application.configure do
  # Set API keys from environment variables
  config.stripe = {
    publishable_key: ENV["STRIPE_PUBLISHABLE_KEY"],
    secret_key: ENV["STRIPE_SECRET_KEY"],
    endpoint_secret: ENV["STRIPE_ENDPOINT_SECRET"],
    webhook_tolerance: 300 # 5 minutes
  }

  if defined?(Stripe)
    # Initialize Stripe with secret key
    Stripe.api_key = config.stripe[:secret_key]

    # Set API version for consistency
    Stripe.api_version = "2024-06-20"

    # Log Stripe requests in development
    Stripe.log_level = Stripe::LEVEL_INFO if Rails.env.development?
  end
end
