# frozen_string_literal: true

module Services
  # Service for managing reverse proxy configuration
  #
  # Provides proxy management including:
  # - Configuration CRUD
  # - URL mapping management
  # - Service validation
  # - Config generation (Nginx, Apache, Traefik)
  # - Health monitoring
  # - Service discovery
  # - Import/Export
  #
  # Usage:
  #   service = Services::ProxyConfigService.new
  #   config = service.get_full_config
  #
  class ProxyConfigService
    Result = Struct.new(:success?, :data, :error, keyword_init: true)

    VALID_PROXY_TYPES = %w[nginx apache traefik].freeze
    VALID_PROTOCOLS = %w[http https tcp ws wss redis postgresql].freeze

    # Get full proxy configuration
    # @return [Hash] Full configuration
    def get_full_config
      {
        service_config: AdminSetting.reverse_proxy_config,
        service_discovery_config: AdminSetting.service_discovery_config,
        service_templates: AdminSetting.service_templates,
        health_status: AdminSetting.proxy_health_status
      }
    end

    # Get proxy status summary
    # @return [Hash] Status summary
    def get_status
      config = AdminSetting.reverse_proxy_config
      {
        enabled: config["enabled"],
        current_environment: config["current_environment"],
        active_mappings: AdminSetting.sorted_url_mappings.count,
        services_configured: config.dig("environments", config["current_environment"])&.keys || [],
        last_updated: AdminSetting.find_by(key: "reverse_proxy_config")&.updated_at
      }
    end

    # Update configuration
    # @param config_type [String] Type of config to update
    # @param config_params [Hash] Configuration parameters
    # @return [Result]
    def update_config(config_type:, config_params:)
      case config_type
      when "service_config"
        AdminSetting.update_reverse_proxy_config(config_params)
      when "service_discovery_config"
        AdminSetting.update_service_discovery_config(config_params)
      when "service_templates"
        AdminSetting.update_service_templates(config_params)
      else
        return Result.new(success?: false, error: "Invalid configuration type")
      end

      Result.new(success?: true, data: { message: "Services configuration updated successfully" })
    rescue StandardError => e
      Result.new(success?: false, error: "Failed to update services configuration: #{e.message}")
    end

    # Validate proxy configuration
    # @param config [Hash] Configuration to validate
    # @return [Hash] Validation result
    def validate_config(config)
      errors = []

      errors << "Missing enabled field" unless config.key?("enabled")
      errors << "Missing environments configuration" unless config.key?("environments")
      errors << "Missing url_mappings configuration" unless config.key?("url_mappings")

      if config["environments"]
        config["environments"].each do |env_name, env_config|
          env_config.each do |service_name, service_config|
            errors << "Missing host for #{service_name} in #{env_name}" unless service_config["host"]
            errors << "Missing port for #{service_name} in #{env_name}" unless service_config["port"]
            errors << "Missing protocol for #{service_name} in #{env_name}" unless service_config["protocol"]
          end
        end
      end

      if config["url_mappings"]
        config["url_mappings"].each_with_index do |mapping, index|
          errors << "Missing pattern for mapping #{index + 1}" unless mapping["pattern"]
          errors << "Missing target_service for mapping #{index + 1}" unless mapping["target_service"]
          errors << "Invalid priority for mapping #{index + 1}" unless mapping["priority"].is_a?(Integer)
        end
      end

      { valid: errors.empty?, errors: errors }
    end

    # Validate service configuration
    # @param service_config [Hash] Service configuration
    # @return [Hash] Validation result
    def validate_service(service_config)
      errors = []
      warnings = []

      if service_config[:host].blank?
        errors << "Host is required"
      elsif !service_config[:host].match?(/\A[\w\.-]+\z/)
        errors << "Host contains invalid characters"
      end

      port = service_config[:port].to_i
      if port < 1 || port > 65535
        errors << "Port must be between 1 and 65535"
      elsif port < 1024 && service_config[:host] != "localhost"
        warnings << "Using privileged port (< 1024) on remote host"
      end

      unless VALID_PROTOCOLS.include?(service_config[:protocol])
        errors << "Protocol must be one of: #{VALID_PROTOCOLS.join(', ')}"
      end

      if service_config[:health_check_path].present? && !service_config[:health_check_path].start_with?("/")
        warnings << "Health check path should start with /"
      end

      { valid: errors.empty?, errors: errors, warnings: warnings }
    end

    # Validate proxy type
    # @param proxy_type [String] Proxy type
    # @return [Boolean]
    def valid_proxy_type?(proxy_type)
      VALID_PROXY_TYPES.include?(proxy_type.to_s.downcase)
    end

    # =============================================================================
    # URL MAPPINGS
    # =============================================================================

    # Create URL mapping
    # @param mapping_data [Hash] Mapping data
    # @return [Hash] Created mapping with ID
    def create_url_mapping(mapping_data)
      mapping_data["id"] = SecureRandom.uuid
      mapping_data["enabled"] = true

      AdminSetting.add_url_mapping(mapping_data)
      mapping_data
    end

    # Update URL mapping
    # @param mapping_id [String] Mapping ID
    # @param mapping_data [Hash] Updated data
    def update_url_mapping(mapping_id, mapping_data)
      AdminSetting.update_url_mapping(mapping_id, mapping_data)
    end

    # Remove URL mapping
    # @param mapping_id [String] Mapping ID
    def remove_url_mapping(mapping_id)
      AdminSetting.remove_url_mapping(mapping_id)
    end

    # Toggle URL mapping
    # @param mapping_id [String] Mapping ID
    # @param enabled [Boolean] Enable/disable
    def toggle_url_mapping(mapping_id, enabled)
      AdminSetting.toggle_url_mapping(mapping_id, enabled)
    end

    # =============================================================================
    # SERVICE MANAGEMENT
    # =============================================================================

    # Add service to configuration
    # @param service_data [Hash] Service data
    # @return [Result]
    def add_service(service_data)
      config = AdminSetting.reverse_proxy_config
      environment = config["current_environment"] || Rails.env

      environments = config["environments"] || {}
      environments[environment] ||= {}
      environments[environment][service_data[:name]] = {
        "host" => service_data[:host],
        "port" => service_data[:port].to_i,
        "protocol" => service_data[:protocol],
        "base_url" => "#{service_data[:protocol]}://#{service_data[:host]}:#{service_data[:port]}",
        "health_check_path" => service_data[:health_check_path]
      }

      AdminSetting.update_reverse_proxy_config("environments" => environments)
      Result.new(success?: true, data: { message: "Service #{service_data[:name]} added to configuration" })
    rescue StandardError => e
      Result.new(success?: false, error: "Failed to add service: #{e.message}")
    end

    # Duplicate service
    # @param environment [String] Environment
    # @param service_name [String] Source service name
    # @param new_name [String] New service name
    # @return [Result]
    def duplicate_service(environment:, service_name:, new_name:)
      config = AdminSetting.reverse_proxy_config
      source_config = config.dig("environments", environment, service_name)

      return Result.new(success?: false, error: "Source service not found") unless source_config
      return Result.new(success?: false, error: "Service with new name already exists") if config.dig("environments", environment, new_name)

      new_service_config = source_config.dup
      new_service_config["port"] += 1
      new_service_config["base_url"] = "#{new_service_config['protocol']}://#{new_service_config['host']}:#{new_service_config['port']}"

      environments = config["environments"] || {}
      environments[environment] ||= {}
      environments[environment][new_name] = new_service_config

      AdminSetting.update_reverse_proxy_config("environments" => environments)
      Result.new(success?: true, data: { message: "Service #{service_name} duplicated as #{new_name}" })
    rescue StandardError => e
      Result.new(success?: false, error: "Failed to duplicate service: #{e.message}")
    end

    # Test service connectivity
    # @param environment [String] Environment
    # @param service_name [String] Service name
    # @return [Hash] Test result
    def test_service(environment:, service_name:)
      config = AdminSetting.reverse_proxy_config
      service_config = config.dig("environments", environment, service_name)

      return { status: "not_found", error: "Service not found in configuration" } unless service_config

      # Perform real connection test
      perform_connection_test(service_config)
    end

    private

    def perform_connection_test(service_config)
      require "net/http"
      require "timeout"

      host = service_config["host"]
      port = service_config["port"].to_i
      protocol = service_config["protocol"] || "http"
      health_check_path = service_config["health_check_path"] || "/"

      # Skip HTTP test for non-HTTP protocols
      return test_tcp_connection(host, port) unless %w[http https].include?(protocol)

      start_time = Time.current

      begin
        Timeout.timeout(10) do
          uri = URI("#{protocol}://#{host}:#{port}#{health_check_path}")
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = protocol == "https"
          http.open_timeout = 5
          http.read_timeout = 5

          response = http.get(uri.path.presence || "/")
          response_time = ((Time.current - start_time) * 1000).round

          {
            status: response.code.to_i < 500 ? "healthy" : "degraded",
            response_code: response.code.to_i,
            response_time: response_time,
            error: nil
          }
        end
      rescue Timeout::Error
        { status: "unreachable", response_code: nil, response_time: nil, error: "Connection timeout" }
      rescue Errno::ECONNREFUSED
        { status: "unreachable", response_code: nil, response_time: nil, error: "Connection refused" }
      rescue StandardError => e
        { status: "error", response_code: nil, response_time: nil, error: e.message }
      end
    end

    def test_tcp_connection(host, port)
      require "socket"
      require "timeout"

      start_time = Time.current

      begin
        Timeout.timeout(5) do
          socket = TCPSocket.new(host, port)
          socket.close
          response_time = ((Time.current - start_time) * 1000).round
          { status: "healthy", response_code: nil, response_time: response_time, error: nil }
        end
      rescue Timeout::Error
        { status: "unreachable", response_code: nil, response_time: nil, error: "Connection timeout" }
      rescue Errno::ECONNREFUSED
        { status: "unreachable", response_code: nil, response_time: nil, error: "Connection refused" }
      rescue StandardError => e
        { status: "error", response_code: nil, response_time: nil, error: e.message }
      end
    end

    public

    # =============================================================================
    # IMPORT/EXPORT
    # =============================================================================

    # Export services for an environment
    # @param environment [String] Environment
    # @return [Hash] Export data
    def export_services(environment)
      config = AdminSetting.reverse_proxy_config
      services = config.dig("environments", environment) || {}

      {
        environment: environment,
        services: services,
        export_format: "json",
        filename: "powernode_services_#{environment}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
      }
    end

    # Import services
    # @param environment [String] Environment
    # @param import_services [Hash] Services to import
    # @return [Hash] Import result
    def import_services(environment:, import_services:)
      config = AdminSetting.reverse_proxy_config
      current_services = config.dig("environments", environment) || {}

      imported_count = 0
      skipped_count = 0
      errors = []

      import_services.each do |service_name, service_config|
        if current_services.key?(service_name)
          skipped_count += 1
          errors << "Service #{service_name} already exists (skipped)"
        elsif service_config["host"].present? && service_config["port"].present?
          current_services[service_name] = service_config
          imported_count += 1
        else
          errors << "Service #{service_name} has invalid configuration (missing host or port)"
        end
      end

      if imported_count > 0
        environments = config["environments"] || {}
        environments[environment] = current_services
        AdminSetting.update_reverse_proxy_config("environments" => environments)
      end

      {
        imported_count: imported_count,
        skipped_count: skipped_count,
        errors: errors,
        message: "Import completed: #{imported_count} imported, #{skipped_count} skipped"
      }
    end

    # =============================================================================
    # SERVICE TEMPLATES
    # =============================================================================

    # Get predefined service templates
    # @return [Array<Hash>] Templates
    def service_templates
      [
        { name: "Frontend (React/Vue)", type: "frontend", description: "Single Page Application frontend service",
          config: { host: "localhost", port: 3000, protocol: "http", health_check_path: "/", base_url: "http://localhost:3000" } },
        { name: "Backend API (Rails/Node)", type: "backend", description: "RESTful API backend service",
          config: { host: "localhost", port: 5000, protocol: "http", health_check_path: "/api/health", base_url: "http://localhost:5000" } },
        { name: "Worker Service (Sidekiq)", type: "worker", description: "Background job processing service",
          config: { host: "localhost", port: 6000, protocol: "http", health_check_path: "/health", base_url: "http://localhost:6000" } },
        { name: "Database (PostgreSQL)", type: "database", description: "PostgreSQL database server",
          config: { host: "localhost", port: 5432, protocol: "postgresql", health_check_path: "", base_url: "postgresql://localhost:5432" } },
        { name: "Cache (Redis)", type: "cache", description: "Redis cache server",
          config: { host: "localhost", port: 6379, protocol: "redis", health_check_path: "", base_url: "redis://localhost:6379" } },
        { name: "Load Balancer (Nginx)", type: "proxy", description: "Nginx load balancer and web server",
          config: { host: "localhost", port: 80, protocol: "http", health_check_path: "/nginx_status", base_url: "http://localhost" } }
      ]
    end

    # =============================================================================
    # HEALTH MONITORING
    # =============================================================================

    # Get health history for a service
    # @param service_name [String] Service name
    # @param hours [Integer] Hours to look back
    # @return [Hash] Health history
    def health_history(service_name:, hours: 24)
      # Fetch real health check data from cache or database
      data_points = fetch_health_history_data(service_name, hours)

      {
        service: service_name,
        timeframe: "Last #{hours} hours",
        data_points: data_points
      }
    end

    # Fetch real health history data from cache or perform current test
    # @param service_name [String] Service name
    # @param hours [Integer] Hours to look back
    # @return [Array<Hash>] Health data points
    def fetch_health_history_data(service_name, hours)
      cache_key = "service_health_history:#{service_name}:#{hours}"

      # Try to fetch from cache first
      cached_data = Rails.cache.read(cache_key)
      return cached_data if cached_data.present?

      # If no cached history, return current status only
      config = AdminSetting.reverse_proxy_config
      environment = config["current_environment"] || Rails.env
      service_config = config.dig("environments", environment, service_name)

      if service_config
        current_test = perform_connection_test(service_config)
        data_points = [ {
          timestamp: Time.current.iso8601,
          status: current_test[:status],
          response_time: current_test[:response_time],
          response_code: current_test[:response_code],
          error: current_test[:error]
        } ]

        # Cache for 5 minutes
        Rails.cache.write(cache_key, data_points, expires_in: 5.minutes)
        data_points
      else
        []
      end
    end

    # Get discovered services (mock)
    # @return [Array<Hash>] Discovered services
    def discovered_services
      [
        { name: "frontend", host: "localhost", port: 3000, protocol: "http", health_check_path: "/health",
          status: "healthy", discovered_method: "port_scan", last_seen: Time.current.iso8601 },
        { name: "backend", host: "localhost", port: 5000, protocol: "http", health_check_path: "/api/health",
          status: "healthy", discovered_method: "dns", last_seen: Time.current.iso8601 }
      ]
    end

    # =============================================================================
    # CONFIG GENERATION
    # =============================================================================

    # Generate Nginx configuration
    # @param config [Hash] Proxy configuration
    # @return [String] Nginx config
    def generate_nginx_config(config)
      nginx_config = "# Powernode Services Configuration\n# Generated at: #{Time.current}\n\n"

      environment = config["current_environment"] || Rails.env
      env_config = config.dig("environments", environment) || {}

      env_config.each do |service_name, service_config|
        nginx_config += "upstream powernode_#{service_name} {\n  server #{service_config['host']}:#{service_config['port']};\n}\n\n"
      end

      nginx_config += "server {\n  listen 80;\n  server_name localhost;\n\n"

      if config.dig("headers", "security_headers", "enabled")
        headers = config.dig("headers", "security_headers") || {}
        nginx_config += "  add_header X-Frame-Options #{headers['x_frame_options'] || 'SAMEORIGIN'} always;\n"
        nginx_config += "  add_header X-Content-Type-Options #{headers['x_content_type_options'] || 'nosniff'} always;\n"
        nginx_config += "  add_header X-XSS-Protection \"#{headers['x_xss_protection'] || '1; mode=block'}\" always;\n\n"
      end

      sorted_mappings = (config["url_mappings"] || []).select { |m| m["enabled"] }.sort_by { |m| m["priority"] || 999 }
      sorted_mappings.each do |mapping|
        nginx_config += "  location #{mapping['pattern']} {\n"
        nginx_config += "    proxy_pass http://powernode_#{mapping['target_service']};\n"
        nginx_config += "    proxy_set_header Host $host;\n"
        nginx_config += "    proxy_set_header X-Real-IP $remote_addr;\n"
        nginx_config += "    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n"
        nginx_config += "    proxy_set_header X-Forwarded-Proto $scheme;\n"
        nginx_config += "  }\n\n"
      end

      nginx_config + "}\n"
    end

    # Get installation instructions
    # @param proxy_type [String] Proxy type
    # @return [String] Instructions
    def installation_instructions(proxy_type)
      case proxy_type.downcase
      when "nginx"
        "1. Save configuration to /etc/nginx/sites-available/powernode\n2. Create symlink: sudo ln -s /etc/nginx/sites-available/powernode /etc/nginx/sites-enabled/\n3. Test configuration: sudo nginx -t\n4. Reload Nginx: sudo systemctl reload nginx"
      else
        "Installation instructions not available for #{proxy_type}"
      end
    end
  end
end
