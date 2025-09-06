# Be sure to restart your server when you modify this file.

# Avoid CORS issues when API is called from the frontend app.
# Handle Cross-Origin Resource Sharing (CORS) in order to accept cross-origin Ajax requests.

# Read more: https://github.com/cyu/rack-cors

# Load allowed origins once at startup (can be reloaded by restarting server)
cors_allowed_origins = begin
  CorsConfigurationService.allowed_origins
rescue StandardError => e
  Rails.logger.error "Failed to load CORS origins: #{e.message}"
  # Fallback to basic development origins
  [
    'http://localhost:3001',
    'http://127.0.0.1:3001', 
  ]
end

Rails.logger.info "CORS: Loaded #{cors_allowed_origins.size} allowed origins"

# CORS configuration with comprehensive headers support
Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins cors_allowed_origins
    
    resource '*',
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true,
      max_age: 600
  end
end
