# frozen_string_literal: true

class AddCorsSettings < ActiveRecord::Migration[8.0]
  def up
    # Add CORS origins setting if it doesn't exist
    unless AdminSetting.exists?(key: 'cors_allowed_origins')
      AdminSetting.create!(
        key: 'cors_allowed_origins',
        value: default_cors_origins.join("\n")
      )
    end

    # Add CORS configuration documentation setting
    unless AdminSetting.exists?(key: 'cors_configuration_help')
      AdminSetting.create!(
        key: 'cors_configuration_help',
        value: cors_help_text
      )
    end
  end

  def down
    AdminSetting.where(key: ['cors_allowed_origins', 'cors_configuration_help']).destroy_all
  end

  private

  def default_cors_origins
    # Default origins to be configured dynamically through environment variables
    # or AdminSettings interface. No hardcoded custom domains.
    origins = []
    
    if Rails.env.development?
      # Add development origins from environment variables
      env_origins = ENV['CORS_DEV_ORIGINS']&.split(',')&.map(&:strip)&.reject(&:blank?)
      origins.concat(env_origins) if env_origins&.any?
      
      # Add basic localhost origins as fallback
      origins += [
        'http://localhost:3001',
        'https://localhost:3001'
      ] if origins.empty?
    end
    
    # Add production origins from environment variables
    prod_origins = ENV['CORS_ALLOWED_ORIGINS']&.split(',')&.map(&:strip)&.reject(&:blank?)
    origins.concat(prod_origins) if prod_origins&.any?
    
    origins.uniq
  end

  def cors_help_text
    <<~HELP
      ## CORS Origins Configuration
      
      Configure allowed origins for Cross-Origin Resource Sharing (CORS).
      
      **Format Options:**
      - `https://example.com` - Exact domain match
      - `http://localhost:3001` - Development servers
      - `/https:\\/\\/[^\\/]+\\.example\\.com\\z/` - Regex pattern for subdomains
      
      **Security Notes:**
      - Always use HTTPS in production
      - Avoid wildcard (*) origins in production
      - Test changes carefully to avoid blocking legitimate requests
      
      **Automatic Sources:**
      - Reverse proxy trusted hosts (from proxy settings)
      - Multi-tenancy wildcard patterns
      - Development localhost origins (in development mode)
      
      Changes take effect immediately without restart.
    HELP
  end
end