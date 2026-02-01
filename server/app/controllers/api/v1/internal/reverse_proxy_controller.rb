# frozen_string_literal: true

class Api::V1::Internal::ReverseProxyController < Api::V1::Internal::InternalBaseController
  # Internal API endpoints for worker service reverse proxy operations
  # These endpoints are called by background workers only

  # POST /api/v1/internal/reverse_proxy/validate
  def validate_config
    config = params.require(:config)

    validation_result = validate_proxy_config(config)

    render_success(validation_result)
  rescue StandardError => e
    Rails.logger.error "Config validation failed: #{e.message}"
    render_error("Configuration validation failed", status: :internal_server_error)
  end

  # POST /api/v1/internal/reverse_proxy/test_connectivity
  def test_connectivity
    config = params.require(:config)

    connectivity_result = test_service_connectivity(config)

    render_success(connectivity_result)
  rescue StandardError => e
    Rails.logger.error "Connectivity test failed: #{e.message}"
    render_error("Connectivity test failed", status: :internal_server_error)
  end

  # POST /api/v1/internal/reverse_proxy/generate_config
  def generate_config
    proxy_type = params.require(:proxy_type)
    config = params.require(:config)

    generated_config = case proxy_type.downcase
    when "nginx"
                        generate_nginx_config(config)
    when "apache"
                        generate_apache_config(config)
    when "traefik"
                        generate_traefik_config(config)
    else
                        raise ArgumentError, "Unsupported proxy type: #{proxy_type}"
    end

    render_success({
      config: generated_config,
      filename: "powernode_#{proxy_type.downcase}.conf",
      instructions: proxy_installation_instructions(proxy_type)
    })
  rescue StandardError => e
    Rails.logger.error "Config generation failed: #{e.message}"
    render_error("Config generation failed", status: :internal_server_error)
  end

  # POST /api/v1/internal/reverse_proxy/service_discovery
  def service_discovery
    discovery_config = params.require(:discovery_config)

    unless discovery_config["enabled"]
      return render_error("Service discovery is not enabled", status: :unprocessable_content)
    end

    discovered_services = []

    discovery_config["methods"].each do |method|
      case method
      when "dns"
        discovered_services.concat(discover_via_dns(discovery_config["dns_config"]))
      when "consul"
        discovered_services.concat(discover_via_consul(discovery_config["consul_config"]))
      when "port_scan"
        discovered_services.concat(discover_via_port_scan(discovery_config["port_scan_config"]))
      when "kubernetes"
        discovered_services.concat(discover_via_kubernetes(discovery_config["kubernetes_config"]))
      end
    end

    render_success({
      services: discovered_services,
      message: "Discovered #{discovered_services.length} services"
    })
  rescue StandardError => e
    Rails.logger.error "Service discovery failed: #{e.message}"
    render_error("Service discovery failed", status: :internal_server_error)
  end

  # POST /api/v1/internal/reverse_proxy/health_check
  def health_check
    environment = params[:environment]
    specific_service = params[:service]

    config = AdminSetting.reverse_proxy_config
    target_env = environment || config["current_environment"] || Rails.env
    env_config = config.dig("environments", target_env) || {}

    results = {}

    services_to_check = if specific_service
                         { specific_service => env_config[specific_service] }
    else
                         env_config
    end.compact

    services_to_check.each do |service_name, service_config|
      results[service_name] = test_single_service(service_config)
    end

    render_success({
      services: results,
      environment: target_env
    })
  rescue StandardError => e
    Rails.logger.error "Health check failed: #{e.message}"
    render_error("Health check failed", status: :internal_server_error)
  end

  # POST /api/v1/internal/reverse_proxy/validate_services
  def validate_services
    service_configs = params.require(:services)

    validations = {}

    service_configs.each do |service_name, service_config|
      validations[service_name] = validate_service_config(service_config)
    end

    render_success({
      validations: validations
    })
  rescue StandardError => e
    Rails.logger.error "Service validation failed: #{e.message}"
    render_error("Service validation failed", status: :internal_server_error)
  end

  private

  def validate_proxy_config(config)
    errors = []

    # Validate basic structure
    errors << "Missing enabled field" unless config.key?("enabled")
    errors << "Missing environments configuration" unless config.key?("environments")
    errors << "Missing url_mappings configuration" unless config.key?("url_mappings")

    # Validate environments
    if config["environments"]
      config["environments"].each do |env_name, env_config|
        env_config.each do |service_name, service_config|
          errors << "Missing host for #{service_name} in #{env_name}" unless service_config["host"]
          errors << "Missing port for #{service_name} in #{env_name}" unless service_config["port"]
          errors << "Missing protocol for #{service_name} in #{env_name}" unless service_config["protocol"]
        end
      end
    end

    # Validate URL mappings
    if config["url_mappings"]
      config["url_mappings"].each_with_index do |mapping, index|
        errors << "Missing pattern for mapping #{index + 1}" unless mapping["pattern"]
        errors << "Missing target_service for mapping #{index + 1}" unless mapping["target_service"]
        errors << "Invalid priority for mapping #{index + 1}" unless mapping["priority"].is_a?(Integer)
      end
    end

    {
      valid: errors.empty?,
      errors: errors
    }
  end

  def test_service_connectivity(config)
    environment = config["current_environment"] || Rails.env
    env_config = config.dig("environments", environment) || {}

    results = {}

    env_config.each do |service_name, service_config|
      results[service_name] = test_single_service(service_config)
    end

    results
  end

  def test_single_service(service_config)
    start_time = Time.current
    health_url = "#{service_config['base_url']}#{service_config['health_check_path']}"

    begin
      uri = URI(health_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 5

      response = http.get(uri.path)
      response_time = ((Time.current - start_time) * 1000).round(2)

      {
        status: response.code == "200" ? "healthy" : "unhealthy",
        response_code: response.code.to_i,
        response_time_ms: response_time,
        url: health_url
      }
    rescue StandardError => e
      {
        status: "unreachable",
        error: e.message,
        url: health_url
      }
    end
  end

  def validate_service_config(service_config)
    errors = []
    warnings = []

    # Validate host
    if service_config["host"].blank?
      errors << "Host is required"
    elsif !service_config["host"].match?(/\A[\w\.-]+\z/)
      errors << "Host contains invalid characters"
    end

    # Validate port
    port = service_config["port"].to_i
    if port < 1 || port > 65535
      errors << "Port must be between 1 and 65535"
    elsif port < 1024 && service_config["host"] != "localhost"
      warnings << "Using privileged port (< 1024) on remote host"
    end

    # Validate protocol
    valid_protocols = %w[http https tcp ws wss redis postgresql]
    unless valid_protocols.include?(service_config["protocol"])
      errors << "Protocol must be one of: #{valid_protocols.join(', ')}"
    end

    # Validate health check path
    if service_config["health_check_path"].present? && !service_config["health_check_path"].start_with?("/")
      warnings << "Health check path should start with /"
    end

    {
      valid: errors.empty?,
      errors: errors,
      warnings: warnings
    }
  end

  def generate_nginx_config(config)
    # Basic Nginx configuration template
    nginx_config = <<~CONFIG
      # Powernode Reverse Proxy Configuration
      # Generated at: #{Time.current}

      upstream powernode_frontend {
    CONFIG

    # Add upstream definitions
    environment = config["current_environment"] || Rails.env
    env_config = config.dig("environments", environment) || {}

    env_config.each do |service_name, service_config|
      nginx_config += "  # #{service_name.capitalize} service\n"
      nginx_config += "  upstream powernode_#{service_name} {\n"
      nginx_config += "    server #{service_config['host']}:#{service_config['port']};\n"
      nginx_config += "  }\n\n"
    end

    # Add server block
    nginx_config += <<~CONFIG
      server {
        listen 80;
        server_name localhost;
      #{'  '}
        # Security headers
    CONFIG

    if config.dig("headers", "security_headers", "enabled")
      headers = config.dig("headers", "security_headers") || {}
      nginx_config += "    add_header X-Frame-Options #{headers['x_frame_options'] || 'SAMEORIGIN'} always;\n"
      nginx_config += "    add_header X-Content-Type-Options #{headers['x_content_type_options'] || 'nosniff'} always;\n"
      nginx_config += "    add_header X-XSS-Protection \"#{headers['x_xss_protection'] || '1; mode=block'}\" always;\n"
    end

    # Add location blocks for URL mappings
    sorted_mappings = (config["url_mappings"] || []).select { |m| m["enabled"] }.sort_by { |m| m["priority"] || 999 }

    sorted_mappings.each do |mapping|
      nginx_config += "\n    # #{mapping['name'] || mapping['pattern']}\n"
      nginx_config += "    location #{mapping['pattern']} {\n"
      nginx_config += "      proxy_pass http://powernode_#{mapping['target_service']};\n"
      nginx_config += "      proxy_set_header Host $host;\n"
      nginx_config += "      proxy_set_header X-Real-IP $remote_addr;\n"
      nginx_config += "      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\n"
      nginx_config += "      proxy_set_header X-Forwarded-Proto $scheme;\n"
      nginx_config += "    }\n"
    end

    nginx_config += "  }\n"
    nginx_config
  end

  def generate_apache_config(config)
    "# Apache configuration generation not implemented yet"
  end

  def generate_traefik_config(config)
    "# Traefik configuration generation not implemented yet"
  end

  def proxy_installation_instructions(proxy_type)
    case proxy_type.downcase
    when "nginx"
      "1. Save configuration to /etc/nginx/sites-available/powernode\n2. Create symlink: sudo ln -s /etc/nginx/sites-available/powernode /etc/nginx/sites-enabled/\n3. Test configuration: sudo nginx -t\n4. Reload Nginx: sudo systemctl reload nginx"
    else
      "Installation instructions not available for #{proxy_type}"
    end
  end

  def discover_via_dns(config)
    return [] unless config["enabled"]

    # Mock DNS discovery - in production would use actual DNS resolution
    [
      {
        name: "api-service",
        host: "api.local",
        port: 80,
        protocol: "http",
        health_check_path: "/health",
        status: "healthy",
        discovered_method: "dns",
        last_seen: Time.current.iso8601
      }
    ]
  end

  def discover_via_consul(config)
    return [] unless config["enabled"]

    # Mock Consul discovery - in production would connect to Consul API
    [
      {
        name: "consul-service",
        host: "10.0.1.5",
        port: 8080,
        protocol: "http",
        health_check_path: "/health",
        status: "healthy",
        discovered_method: "consul",
        last_seen: Time.current.iso8601
      }
    ]
  end

  def discover_via_port_scan(config)
    return [] unless config["enabled"]

    # Mock port scan discovery
    discovered = []
    config["port_ranges"].each do |service_type, (start_port, end_port)|
      # Simulate finding a service in the port range
      discovered << {
        name: "#{service_type}-discovered",
        host: "localhost",
        port: start_port + 1, # Pretend we found something on start_port + 1
        protocol: "http",
        health_check_path: service_type == "backend" ? "/api/health" : "/health",
        status: "healthy",
        discovered_method: "port_scan",
        last_seen: Time.current.iso8601
      }
    end
    discovered
  end

  def discover_via_kubernetes(config)
    return [] unless config["enabled"]

    # Mock Kubernetes discovery - in production would use k8s API
    [
      {
        name: "k8s-service",
        host: "10.0.2.10",
        port: 3000,
        protocol: "http",
        health_check_path: "/health",
        status: "healthy",
        discovered_method: "kubernetes",
        last_seen: Time.current.iso8601
      }
    ]
  end
end
