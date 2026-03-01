# frozen_string_literal: true

# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

# Dynamic CORS origin checking using CorsConfigurationService
# This approach avoids class loading issues during initialization
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Use a proc to dynamically check origins at runtime
    origins do |source, _env|
      begin
        # Lazy-load and check if origin is allowed
        CorsConfigurationService.origin_allowed?(source)
      rescue StandardError => e
        Rails.logger.error "CORS origin check failed: #{e.message}"
        if Rails.env.development?
          source.start_with?("http://localhost") || source.start_with?("http://127.0.0.1")
        else
          Rails.logger.warn "CORS: Rejecting origin #{source} due to service error"
          false
        end
      end
    end

    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      credentials: true,
      max_age: 600
  end
end
