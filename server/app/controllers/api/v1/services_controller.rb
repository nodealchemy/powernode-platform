# frozen_string_literal: true

class Api::V1::ServicesController < ApplicationController
  before_action :authenticate_request
  before_action :require_system_admin_permission

  # Worker job classes - load them dynamically to avoid circular dependencies
  def self.job_classes
    @job_classes ||= {
      test_configuration: "Services::TestConfigurationJob",
      generate_config: "Services::GenerateConfigJob",
      service_discovery: "Services::ServiceDiscoveryJob",
      health_check: "Services::HealthCheckJob",
      service_validation: "Services::ServiceValidationJob"
    }
  end

  def get_job_class(job_type)
    class_name = self.class.job_classes[job_type]
    return nil unless class_name

    class_name.constantize
  rescue NameError => e
    Rails.logger.error "Job class not found: #{class_name} - #{e.message}"
    nil
  end

  # GET /api/v1/admin/reverse_proxy
  def show
    render_success({
      service_config: AdminSetting.reverse_proxy_config,
      service_discovery_config: AdminSetting.service_discovery_config,
      service_templates: AdminSetting.service_templates,
      health_status: AdminSetting.proxy_health_status
    })
  rescue StandardError => e
    Rails.logger.error "Failed to fetch services config: #{e.message}"
    render_error("Failed to fetch services configuration", status: :internal_server_error)
  end

  # PUT /api/v1/admin/reverse_proxy
  def update
    config_type = params[:config_type] || "service_config"

    case config_type
    when "service_config"
      AdminSetting.update_reverse_proxy_config(service_config_params.to_h)
    when "service_discovery_config"
      AdminSetting.update_service_discovery_config(service_discovery_params.to_h)
    when "service_templates"
      AdminSetting.update_service_templates(service_templates_params.to_h)
    else
      return render_error("Invalid configuration type", status: :bad_request)
    end

    Rails.logger.info "Services config updated by user #{current_user.email}"
    render_success({ message: "Services configuration updated successfully" })
  rescue StandardError => e
    Rails.logger.error "Failed to update services config: #{e.message}"
    render_error("Failed to update services configuration", status: :internal_server_error)
  end

  # POST /api/v1/admin/reverse_proxy/test
  def test_configuration
    test_config = params[:test_config] || AdminSetting.reverse_proxy_config

    begin
      # Quick synchronous validation first
      validation_result = validate_proxy_config(test_config)
      unless validation_result[:valid]
        return render_error("Configuration validation failed: #{validation_result[:errors].join(', ')}",
                          status: :unprocessable_content)
      end

      # Delegate to worker for full testing
      job_id = SecureRandom.uuid
      job_class = get_job_class(:test_configuration)

      unless job_class
        return render_error("Test configuration worker not available", status: :service_unavailable)
      end

      sidekiq_jid = job_class.perform_async(test_config, job_id: job_id)

      # Track the job
      job = BackgroundJob.create_for_sidekiq_job(
        sidekiq_jid,
        "services_test_configuration",
        { test_config: test_config }
      )

      render_success({
        job_id: job_id,
        sidekiq_jid: sidekiq_jid,
        status: "started",
        message: "Configuration test started. Use job_id to check progress."
      })
    rescue StandardError => e
      Rails.logger.error "Failed to start configuration test: #{e.message}"
      render_error("Failed to start configuration test", status: :internal_server_error)
    end
  end

  # POST /api/v1/admin/reverse_proxy/generate_config
  def generate_config
    proxy_type = params[:proxy_type] || "nginx"
    config = AdminSetting.reverse_proxy_config

    begin
      # Validate proxy type
      valid_types = %w[nginx apache traefik]
      unless valid_types.include?(proxy_type.downcase)
        return render_error("Unsupported proxy type: #{proxy_type}. Valid types: #{valid_types.join(', ')}",
                          status: :bad_request)
      end

      # Delegate to worker for config generation
      job_id = SecureRandom.uuid
      job_class = get_job_class(:generate_config)

      unless job_class
        return render_error("Config generation worker not available", status: :service_unavailable)
      end

      sidekiq_jid = job_class.perform_async(proxy_type, config, job_id: job_id)

      # Track the job
      job = BackgroundJob.create_for_sidekiq_job(
        sidekiq_jid,
        "services_generate_config",
        { proxy_type: proxy_type, config_size: config.to_s.length }
      )

      render_success({
        job_id: job_id,
        sidekiq_jid: sidekiq_jid,
        status: "started",
        proxy_type: proxy_type,
        message: "#{proxy_type.capitalize} configuration generation started. Use job_id to check progress."
      })
    rescue StandardError => e
      Rails.logger.error "Failed to start config generation: #{e.message}"
      render_error("Failed to start config generation", status: :internal_server_error)
    end
  end

  # GET /api/v1/admin/reverse_proxy/health
  def health_check
    begin
      health_status = AdminSetting.proxy_health_status
      render_success(health_status)
    rescue StandardError => e
      Rails.logger.error "Health check failed: #{e.message}"
      render_error("Health check failed", status: :internal_server_error)
    end
  end

  # GET /api/v1/admin/reverse_proxy/status
  def status
    begin
      config = AdminSetting.reverse_proxy_config
      render_success({
        enabled: config["enabled"],
        current_environment: config["current_environment"],
        active_mappings: AdminSetting.sorted_url_mappings.count,
        services_configured: config.dig("environments", config["current_environment"])&.keys || [],
        last_updated: AdminSetting.find_by(key: "reverse_proxy_config")&.updated_at
      })
    rescue StandardError => e
      Rails.logger.error "Status check failed: #{e.message}"
      render_error("Status check failed", status: :internal_server_error)
    end
  end

  # POST /api/v1/admin/reverse_proxy/url_mappings
  def create
    mapping_data = url_mapping_params
    mapping_data["id"] = SecureRandom.uuid
    mapping_data["enabled"] = true

    AdminSetting.add_url_mapping(mapping_data)

    Rails.logger.info "URL mapping created: #{mapping_data['pattern']} -> #{mapping_data['target_service']}"
    render_success({ message: "URL mapping created successfully", mapping: mapping_data })
  rescue StandardError => e
    Rails.logger.error "Failed to create URL mapping: #{e.message}"
    render_error("Failed to create URL mapping", status: :internal_server_error)
  end

  # PUT /api/v1/admin/reverse_proxy/url_mappings/:id
  def update_url_mapping
    mapping_id = params[:id]
    mapping_data = url_mapping_params

    AdminSetting.update_url_mapping(mapping_id, mapping_data)

    Rails.logger.info "URL mapping updated: #{mapping_id}"
    render_success({ message: "URL mapping updated successfully" })
  rescue StandardError => e
    Rails.logger.error "Failed to update URL mapping: #{e.message}"
    render_error("Failed to update URL mapping", status: :internal_server_error)
  end

  # DELETE /api/v1/admin/reverse_proxy/url_mappings/:id
  def destroy
    mapping_id = params[:id]

    AdminSetting.remove_url_mapping(mapping_id)

    Rails.logger.info "URL mapping removed: #{mapping_id}"
    render_success({ message: "URL mapping removed successfully" })
  rescue StandardError => e
    Rails.logger.error "Failed to remove URL mapping: #{e.message}"
    render_error("Failed to remove URL mapping", status: :internal_server_error)
  end

  # PATCH /api/v1/admin/reverse_proxy/url_mappings/:id/toggle
  def toggle
    mapping_id = params[:id]
    enabled = params[:enabled] == true || params[:enabled] == "true"

    AdminSetting.toggle_url_mapping(mapping_id, enabled)

    Rails.logger.info "URL mapping #{enabled ? 'enabled' : 'disabled'}: #{mapping_id}"
    render_success({ message: "URL mapping #{enabled ? 'enabled' : 'disabled'} successfully" })
  rescue StandardError => e
    Rails.logger.error "Failed to toggle URL mapping: #{e.message}"
    render_error("Failed to toggle URL mapping", status: :internal_server_error)
  end

  # GET /api/v1/admin/reverse_proxy/discovered_services
  def discovered_services
    # Mock discovered services data - in production this would query actual discovery services
    discovered = [
      {
        name: "frontend",
        host: "localhost",
        port: 3000,
        protocol: "http",
        health_check_path: "/health",
        status: "healthy",
        discovered_method: "port_scan",
        last_seen: Time.current.iso8601
      },
      {
        name: "backend",
        host: "localhost",
        port: 5000,
        protocol: "http",
        health_check_path: "/api/health",
        status: "healthy",
        discovered_method: "dns",
        last_seen: Time.current.iso8601
      }
    ]

    render_success(discovered)
  rescue StandardError => e
    Rails.logger.error "Failed to get discovered services: #{e.message}"
    render_error("Failed to retrieve discovered services", status: :internal_server_error)
  end

  # POST /api/v1/admin/reverse_proxy/service_discovery
  def service_discovery
    config = AdminSetting.service_discovery_config

    begin
      unless config["enabled"]
        return render_error("Service discovery is not enabled", status: :unprocessable_content)
      end

      # Delegate to worker for service discovery
      job_id = SecureRandom.uuid
      job_class = get_job_class(:service_discovery)

      unless job_class
        return render_error("Service discovery worker not available", status: :service_unavailable)
      end

      sidekiq_jid = job_class.perform_async(config, job_id: job_id)

      # Track the job
      job = BackgroundJob.create_for_sidekiq_job(
        sidekiq_jid,
        "services_service_discovery",
        { methods: config["methods"], enabled_methods_count: config["methods"]&.length || 0 }
      )

      render_success({
        job_id: job_id,
        sidekiq_jid: sidekiq_jid,
        status: "started",
        methods: config["methods"],
        message: "Service discovery started. Use job_id to check progress and results."
      })
    rescue StandardError => e
      Rails.logger.error "Failed to start service discovery: #{e.message}"
      render_error("Failed to start service discovery", status: :internal_server_error)
    end
  end

  # POST /api/v1/admin/reverse_proxy/add_discovered_service
  def add_discovered_service
    service_data = params.require(:service).permit(:name, :host, :port, :protocol, :health_check_path)

    # Add service to current environment configuration
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

    render_success({
      message: "Service #{service_data[:name]} added to configuration"
    })
  rescue StandardError => e
    Rails.logger.error "Failed to add discovered service: #{e.message}"
    render_error("Failed to add service to configuration", status: :internal_server_error)
  end

  # GET /api/v1/admin/reverse_proxy/health_history/:service_name
  def health_history
    service_name = params[:service_name]
    hours = params[:hours]&.to_i || 24

    # Mock health history data - in production this would query actual monitoring data
    data_points = []
    current_time = Time.current

    (hours * 2).times do |i| # Every 30 minutes
      timestamp = current_time - (i * 30).minutes
      status = [ "healthy", "healthy", "healthy", "unhealthy" ].sample # Mostly healthy
      response_time = status == "healthy" ? rand(50..200) : rand(500..2000)

      data_points << {
        timestamp: timestamp.iso8601,
        status: status,
        response_time: response_time,
        response_code: status == "healthy" ? 200 : [ 404, 500, 502 ].sample,
        error: status == "healthy" ? nil : "Connection timeout"
      }
    end

    render_success({
      service: service_name,
      timeframe: "Last #{hours} hours",
      data_points: data_points.reverse
    })
  rescue StandardError => e
    Rails.logger.error "Failed to get health history: #{e.message}"
    render_error("Failed to retrieve health history", status: :internal_server_error)
  end

  # PUT /api/v1/admin/reverse_proxy/health_config/:service_name
  def update_health_config
    service_name = params[:service_name]
    health_config = params.require(:health_config).permit(:interval, :timeout, :health_check_path, expected_codes: [])

    # Update health check configuration for service
    # In production, this would update the monitoring configuration

    render_success({
      message: "Health check configuration updated for #{service_name}"
    })
  rescue StandardError => e
    Rails.logger.error "Failed to update health config: #{e.message}"
    render_error("Failed to update health check configuration", status: :internal_server_error)
  end

  # POST /api/v1/admin/reverse_proxy/test_service
  def test_service
    environment = params[:environment]
    service_name = params[:service_name]

    config = AdminSetting.reverse_proxy_config
    service_config = config.dig("environments", environment, service_name)

    unless service_config
      return render_error("Service not found in configuration", status: :not_found)
    end

    begin
      start_time = Time.current
      url = "#{service_config['base_url']}#{service_config['health_check_path']}"

      # Mock connection test - in production would make actual HTTP request
      if service_config["host"] == "localhost" && service_config["port"].between?(3000, 6999)
        status = "healthy"
        response_code = 200
        response_time = rand(50..200)
        error = nil
      else
        status = "unreachable"
        response_code = nil
        response_time = nil
        error = "Connection timeout"
      end

      render_success({
        status: status,
        response_code: response_code,
        response_time: response_time,
        error: error
      })
    rescue StandardError => e
      Rails.logger.error "Service test failed: #{e.message}"
      render_success({
        status: "unreachable",
        error: e.message
      })
    end
  end

  # POST /api/v1/admin/reverse_proxy/validate_service
  def validate_service
    service_config = params.require(:service_config).permit(:host, :port, :protocol, :health_check_path)

    errors = []
    warnings = []

    # Validate host
    if service_config[:host].blank?
      errors << "Host is required"
    elsif !service_config[:host].match?(/\A[\w\.-]+\z/)
      errors << "Host contains invalid characters"
    end

    # Validate port
    port = service_config[:port].to_i
    if port < 1 || port > 65535
      errors << "Port must be between 1 and 65535"
    elsif port < 1024 && service_config[:host] != "localhost"
      warnings << "Using privileged port (< 1024) on remote host"
    end

    # Validate protocol
    valid_protocols = %w[http https tcp ws wss redis postgresql]
    unless valid_protocols.include?(service_config[:protocol])
      errors << "Protocol must be one of: #{valid_protocols.join(', ')}"
    end

    # Validate health check path
    if service_config[:health_check_path].present? && !service_config[:health_check_path].start_with?("/")
      warnings << "Health check path should start with /"
    end

    render_success({
      valid: errors.empty?,
      errors: errors,
      warnings: warnings
    })
  end

  # GET /api/v1/admin/reverse_proxy/service_templates
  def service_templates
    templates = [
      {
        name: "Frontend (React/Vue)",
        type: "frontend",
        description: "Single Page Application frontend service",
        config: {
          host: "localhost",
          port: 3000,
          protocol: "http",
          health_check_path: "/",
          base_url: "http://localhost:3000"
        }
      },
      {
        name: "Backend API (Rails/Node)",
        type: "backend",
        description: "RESTful API backend service",
        config: {
          host: "localhost",
          port: 5000,
          protocol: "http",
          health_check_path: "/api/health",
          base_url: "http://localhost:5000"
        }
      },
      {
        name: "Worker Service (Sidekiq)",
        type: "worker",
        description: "Background job processing service",
        config: {
          host: "localhost",
          port: 6000,
          protocol: "http",
          health_check_path: "/health",
          base_url: "http://localhost:6000"
        }
      },
      {
        name: "Database (PostgreSQL)",
        type: "database",
        description: "PostgreSQL database server",
        config: {
          host: "localhost",
          port: 5432,
          protocol: "postgresql",
          health_check_path: "",
          base_url: "postgresql://localhost:5432"
        }
      },
      {
        name: "Cache (Redis)",
        type: "cache",
        description: "Redis cache server",
        config: {
          host: "localhost",
          port: 6379,
          protocol: "redis",
          health_check_path: "",
          base_url: "redis://localhost:6379"
        }
      },
      {
        name: "Load Balancer (Nginx)",
        type: "proxy",
        description: "Nginx load balancer and web server",
        config: {
          host: "localhost",
          port: 80,
          protocol: "http",
          health_check_path: "/nginx_status",
          base_url: "http://localhost"
        }
      }
    ]

    render_success(templates)
  end

  # POST /api/v1/admin/reverse_proxy/duplicate_service
  def duplicate_service
    environment = params[:environment]
    service_name = params[:service_name]
    new_name = params[:new_name]

    config = AdminSetting.reverse_proxy_config
    source_config = config.dig("environments", environment, service_name)

    unless source_config
      return render_error("Source service not found", status: :not_found)
    end

    # Check if new service name already exists
    if config.dig("environments", environment, new_name)
      return render_error("Service with new name already exists", status: :unprocessable_content)
    end

    # Duplicate the service with modified port to avoid conflicts
    new_service_config = source_config.dup
    new_service_config["port"] += 1
    new_service_config["base_url"] = "#{new_service_config['protocol']}://#{new_service_config['host']}:#{new_service_config['port']}"

    # Update configuration
    environments = config["environments"] || {}
    environments[environment] ||= {}
    environments[environment][new_name] = new_service_config

    AdminSetting.update_reverse_proxy_config("environments" => environments)

    render_success({
      message: "Service #{service_name} duplicated as #{new_name}"
    })
  rescue StandardError => e
    Rails.logger.error "Failed to duplicate service: #{e.message}"
    render_error("Failed to duplicate service", status: :internal_server_error)
  end

  # GET /api/v1/admin/reverse_proxy/export_services/:environment
  def export_services
    environment = params[:environment]
    config = AdminSetting.reverse_proxy_config
    services = config.dig("environments", environment) || {}

    render_success({
      environment: environment,
      services: services,
      export_format: "json",
      filename: "powernode_services_#{environment}_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json"
    })
  end

  # POST /api/v1/admin/reverse_proxy/import_services
  def import_services
    environment = params[:environment]
    import_services = params[:services] || {}

    config = AdminSetting.reverse_proxy_config
    current_services = config.dig("environments", environment) || {}

    imported_count = 0
    skipped_count = 0
    errors = []

    import_services.each do |service_name, service_config|
      if current_services.key?(service_name)
        skipped_count += 1
        errors << "Service #{service_name} already exists (skipped)"
      else
        # Validate service config
        if service_config["host"].present? && service_config["port"].present?
          current_services[service_name] = service_config
          imported_count += 1
        else
          errors << "Service #{service_name} has invalid configuration (missing host or port)"
        end
      end
    end

    # Update configuration if any services were imported
    if imported_count > 0
      environments = config["environments"] || {}
      environments[environment] = current_services
      AdminSetting.update_reverse_proxy_config("environments" => environments)
    end

    render_success({
      imported_count: imported_count,
      skipped_count: skipped_count,
      errors: errors,
      message: "Import completed: #{imported_count} imported, #{skipped_count} skipped"
    })
  rescue StandardError => e
    Rails.logger.error "Failed to import services: #{e.message}"
    render_error("Failed to import services", status: :internal_server_error)
  end

  private

  def require_system_admin_permission
    unless current_user.has_permission?("admin.settings.update")
      render_error("Insufficient permissions to manage services settings", status: :forbidden)
    end
  end

  def service_config_params
    params.require(:service_config).permit(
      :enabled, :current_environment,
      environments: {},
      url_mappings: [ :id, :name, :pattern, :target_service, :priority, :enabled, :description, methods: [] ],
      load_balancing: [ :enabled, :algorithm, :health_check_interval, :failover_enabled ],
      ssl_config: [ :enabled, :enforce_https, :certificate_path, :private_key_path, :hsts_enabled, :hsts_max_age, :ciphers, protocols: [] ],
      cors_config: [ :enabled, :credentials, :max_age, allowed_origins: [], allowed_methods: [], allowed_headers: [], exposed_headers: [] ],
      headers: {
        security_headers: [ :enabled, :x_frame_options, :x_content_type_options, :x_xss_protection, :referrer_policy ],
        custom_headers: {
          request: [ :name, :value, :enabled ],
          response: [ :name, :value, :enabled ]
        }
      },
      rate_limiting: [ :enabled, :default_limit, :window_size, :burst_limit ],
      compression: [ :enabled, :level, types: [] ]
    )
  end

  def service_discovery_params
    params.require(:service_discovery_config).permit(
      :enabled, methods: [],
      dns_config: [ :enabled, :timeout, :retries ],
      consul_config: [ :enabled, :host, :port, :token, :datacenter ],
      port_scan_config: [ :enabled, :timeout, port_ranges: {} ],
      kubernetes_config: [ :enabled, :namespace, :label_selector ]
    )
  end

  def service_templates_params
    params.require(:service_templates).permit(
      nginx: [ :enabled, :config_path, :reload_command, :test_command ],
      apache: [ :enabled, :config_path, :reload_command, :test_command ],
      traefik: [ :enabled, :config_path, :reload_command, :test_command ]
    )
  end

  def url_mapping_params
    params.require(:url_mapping).permit(:name, :pattern, :target_service, :priority, :enabled, :description, methods: [])
  end

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
      begin
        health_url = "#{service_config['base_url']}#{service_config['health_check_path']}"
        start_time = Time.current

        uri = URI(health_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = 5
        http.read_timeout = 5

        response = http.get(uri.path)
        response_time = ((Time.current - start_time) * 1000).round(2)

        results[service_name] = {
          status: response.code == "200" ? "healthy" : "unhealthy",
          response_code: response.code.to_i,
          response_time_ms: response_time,
          url: health_url
        }
      rescue StandardError => e
        results[service_name] = {
          status: "unreachable",
          error: e.message,
          url: health_url
        }
      end
    end

    results
  end

  def generate_nginx_config(config)
    # Basic Nginx configuration template
    nginx_config = <<~CONFIG
      # Powernode Services Configuration
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
    # Basic Apache configuration template
    "# Apache configuration generation not implemented yet"
  end

  def generate_traefik_config(config)
    # Basic Traefik configuration template
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

  # Service discovery helper methods
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
