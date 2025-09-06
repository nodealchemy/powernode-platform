# frozen_string_literal: true

# Dynamic CORS Configuration Service
# Provides CORS origins based on AdminSettings configuration
class CorsConfigurationService
  class << self
    # Get allowed origins for CORS configuration
    def allowed_origins
      return fallback_origins unless defined?(AdminSetting)

      origins = Set.new

      # Add origins from reverse proxy settings
      proxy_config = AdminSetting.reverse_proxy_url_config
      add_proxy_origins(origins, proxy_config)

      # Add custom CORS origins from settings
      add_custom_cors_origins(origins)

      # Always include development origins in development
      add_development_origins(origins) if Rails.env.development?

      # Convert to array and sort for consistency
      origins.to_a.sort
    rescue StandardError => e
      Rails.logger.error "Failed to load CORS configuration: #{e.message}"
      fallback_origins
    end

    # Check if CORS is configured for a specific origin
    def origin_allowed?(origin)
      return false if origin.blank?

      allowed_origins.any? do |allowed|
        if allowed.start_with?('/')
          # Regex pattern
          regex = Regexp.new(allowed[1..-2]) # Remove leading and trailing slashes
          regex.match?(origin)
        else
          # Exact match
          allowed == origin
        end
      end
    rescue StandardError
      false
    end

    # Get CORS methods allowed
    def allowed_methods
      %w[GET POST PUT PATCH DELETE OPTIONS HEAD]
    end

    # Get CORS headers allowed
    def allowed_headers
      %w[
        Accept
        Accept-Language
        Authorization
        Cache-Control
        Content-Language
        Content-Type
        DNT
        If-Modified-Since
        Keep-Alive
        Origin
        User-Agent
        X-Requested-With
      ]
    end

    # Check if credentials are allowed
    def allow_credentials?
      true
    end

    # Get max age for preflight cache
    def max_age
      7200 # 2 hours
    end

    private

    # Add origins from reverse proxy configuration
    def add_proxy_origins(origins, config)
      return unless config.is_a?(Hash)

      # Add trusted hosts
      if config[:trusted_hosts].is_a?(Array)
        config[:trusted_hosts].each do |host|
          add_secure_origin(origins, host)
        end
      end

      # Add default host
      if config[:default_host].present?
        add_secure_origin(origins, config[:default_host])
      end

      # Add wildcard patterns for multi-tenancy
      if config.dig(:multi_tenancy, :wildcard_patterns).is_a?(Array)
        config[:multi_tenancy][:wildcard_patterns].each do |pattern|
          add_secure_origin(origins, pattern)
        end
      end
    end

    # Add custom CORS origins from admin settings
    def add_custom_cors_origins(origins)
      setting = AdminSetting.find_by(key: 'cors_allowed_origins')
      return unless setting&.value.present?

      cors_origins = parse_cors_origins(setting.value)
      cors_origins.each { |origin| origins.add(origin) }
    end

    # Parse CORS origins from setting value
    def parse_cors_origins(value)
      case value
      when String
        # Try to parse as JSON first, then fallback to comma-separated
        begin
          parsed = JSON.parse(value)
          return parsed.map(&:to_s).reject(&:blank?) if parsed.is_a?(Array)
        rescue JSON::ParserError
          # Fallback to comma or newline separated
        end
        value.split(/[,\n]/).map(&:strip).reject(&:blank?)
      when Array
        value.map(&:to_s).reject(&:blank?)
      else
        []
      end
    end

    # Add secure origin (HTTPS preferred)
    def add_secure_origin(origins, host)
      return if host.blank?

      # Skip if it's already a full URL
      if host.start_with?('http://', 'https://')
        origins.add(host)
        return
      end

      # Handle wildcard patterns
      if host.start_with?('*.')
        domain = host[2..]  # Remove the "*." prefix
        origins.add("https://#{domain}")
        origins.add("http://#{domain}") if Rails.env.development?
        # Add the wildcard pattern as a regex
        origins.add("/\\Ahttps:\\/\\/[^\\/]+\\.#{Regexp.escape(domain)}\\z/")
        origins.add("/\\Ahttp:\\/\\/[^\\/]+\\.#{Regexp.escape(domain)}\\z/") if Rails.env.development?
        return
      end

      # Add both HTTP and HTTPS for flexibility
      origins.add("https://#{host}")
      origins.add("http://#{host}") if Rails.env.development?
    end

    # Add development origins from environment variables
    def add_env_development_origins(dev_origins)
      # Check for CORS_DEV_ORIGINS environment variable
      env_origins = ENV['CORS_DEV_ORIGINS']&.split(',')&.map(&:strip)&.reject(&:blank?)
      dev_origins.concat(env_origins) if env_origins&.any?
      
      # Check for FRONTEND_URL environment variable (common in deployment)
      frontend_url = ENV['FRONTEND_URL']
      dev_origins << frontend_url if frontend_url.present?
      
      # Check for VITE_PUBLIC_URL (Vite standard)
      vite_url = ENV['VITE_PUBLIC_URL'] 
      dev_origins << vite_url if vite_url.present?
    end

    # Add development-specific origins
    def add_development_origins(origins)
      dev_origins = [
        'http://localhost:3000',
        'http://localhost:3001',
        'https://localhost:3000',
        'https://localhost:3001',
        'http://127.0.0.1:3000',
        'http://127.0.0.1:3001'
      ]
      
      # Add development origins from environment variables
      add_env_development_origins(dev_origins)

      dev_origins.each { |origin| origins.add(origin) }

      # Local network patterns for development
      origins.add('/\\Ahttp:\\/\\/192\\.168\\.\\d{1,3}\\.\\d{1,3}:300[0-9]\\z/')
      origins.add('/\\Ahttp:\\/\\/10\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}:300[0-9]\\z/')
      origins.add('/\\Ahttp:\\/\\/172\\.(1[6-9]|2[0-9]|3[0-1])\\.\\d{1,3}\\.\\d{1,3}:300[0-9]\\z/')
      
      # Development hostname patterns (allow frontend port 3001 to access backend port 3000)
      origins.add('/\\Ahttp:\\/\\/[^\\/\\.]+\\.(ipnode\\.net|ipnode\\.org|powernode\\.dev|powernode\\.org|local|test):300[0-9]\\z/')
      origins.add('/\\Ahttps:\\/\\/[^\\/\\.]+\\.(ipnode\\.net|ipnode\\.org|powernode\\.dev|powernode\\.org|local|test):300[0-9]\\z/')
    end

    # Fallback origins when database is unavailable
    def fallback_origins
      if Rails.env.development?
        [
          'http://localhost:3000',
          'http://localhost:3001',
          'https://localhost:3000',
          'https://localhost:3001',
          'http://127.0.0.1:3000',
          'http://127.0.0.1:3001'
        ]
      else
        ['https://powernode.dev', 'https://www.powernode.dev']
      end
    end
  end
end