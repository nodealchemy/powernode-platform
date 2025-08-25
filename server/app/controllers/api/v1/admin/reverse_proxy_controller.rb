# frozen_string_literal: true

class Api::V1::Admin::ReverseProxyController < ApplicationController
  include ApiResponse
  
  before_action :authenticate_request
  before_action :require_system_admin_permission

  # GET /api/v1/admin/reverse_proxy
  def show
    render_success({
      reverse_proxy_config: AdminSetting.reverse_proxy_config,
      service_discovery_config: AdminSetting.service_discovery_config,
      proxy_templates: AdminSetting.proxy_templates,
      health_status: AdminSetting.proxy_health_status
    })
  rescue => e
    Rails.logger.error "Failed to fetch reverse proxy config: #{e.message}"
    render_error('Failed to fetch reverse proxy configuration', status: :internal_server_error)
  end

  # PUT /api/v1/admin/reverse_proxy
  def update
    config_type = params[:config_type] || 'reverse_proxy_config'
    
    case config_type
    when 'reverse_proxy_config'
      AdminSetting.update_reverse_proxy_config(reverse_proxy_params)
    when 'service_discovery_config'
      AdminSetting.update_service_discovery_config(service_discovery_params)
    when 'proxy_templates'
      AdminSetting.update_proxy_templates(proxy_templates_params)
    else
      return render_error('Invalid configuration type', status: :bad_request)
    end

    Rails.logger.info "Reverse proxy config updated by user #{current_user.email}"
    render_success({ message: 'Reverse proxy configuration updated successfully' })
  rescue => e
    Rails.logger.error "Failed to update reverse proxy config: #{e.message}"
    render_error('Failed to update reverse proxy configuration', status: :internal_server_error)
  end

  # POST /api/v1/admin/reverse_proxy/test
  def test_configuration
    test_config = params[:test_config] || AdminSetting.reverse_proxy_config
    
    begin
      # Validate configuration structure
      validation_result = validate_proxy_config(test_config)
      unless validation_result[:valid]
        return render_error("Configuration validation failed: #{validation_result[:errors].join(', ')}", 
                          status: :unprocessable_entity)
      end

      # Test service connectivity
      connectivity_result = test_service_connectivity(test_config)
      
      render_success({
        validation: validation_result,
        connectivity: connectivity_result,
        message: 'Configuration test completed'
      })
    rescue => e
      Rails.logger.error "Configuration test failed: #{e.message}"
      render_error('Configuration test failed', status: :internal_server_error)
    end
  end

  # POST /api/v1/admin/reverse_proxy/generate_config
  def generate_config
    proxy_type = params[:proxy_type] || 'nginx'
    config = AdminSetting.reverse_proxy_config
    
    begin
      case proxy_type.downcase
      when 'nginx'
        generated_config = generate_nginx_config(config)
      when 'apache'
        generated_config = generate_apache_config(config)
      when 'traefik'
        generated_config = generate_traefik_config(config)
      else
        return render_error('Unsupported proxy type', status: :bad_request)
      end

      render_success({
        proxy_type: proxy_type,
        config: generated_config,
        filename: "powernode_#{proxy_type}.conf",
        instructions: proxy_installation_instructions(proxy_type)
      })
    rescue => e
      Rails.logger.error "Config generation failed: #{e.message}"
      render_error('Failed to generate proxy configuration', status: :internal_server_error)
    end
  end

  # GET /api/v1/admin/reverse_proxy/health
  def health_check
    begin
      health_status = AdminSetting.proxy_health_status
      render_success(health_status)
    rescue => e
      Rails.logger.error "Health check failed: #{e.message}"
      render_error('Health check failed', status: :internal_server_error)
    end
  end

  # GET /api/v1/admin/reverse_proxy/status
  def status
    begin
      config = AdminSetting.reverse_proxy_config
      render_success({
        enabled: config['enabled'],
        current_environment: config['current_environment'],
        active_mappings: AdminSetting.sorted_url_mappings.count,
        services_configured: config.dig('environments', config['current_environment'])&.keys || [],
        last_updated: AdminSetting.find_by(key: 'reverse_proxy_config')&.updated_at
      })
    rescue => e
      Rails.logger.error "Status check failed: #{e.message}"
      render_error('Status check failed', status: :internal_server_error)
    end
  end

  # POST /api/v1/admin/reverse_proxy/url_mappings
  def create
    mapping_data = url_mapping_params
    mapping_data['id'] = SecureRandom.uuid
    mapping_data['enabled'] = true
    
    AdminSetting.add_url_mapping(mapping_data)
    
    Rails.logger.info "URL mapping created: #{mapping_data['pattern']} -> #{mapping_data['target_service']}"
    render_success({ message: 'URL mapping created successfully', mapping: mapping_data })
  rescue => e
    Rails.logger.error "Failed to create URL mapping: #{e.message}"
    render_error('Failed to create URL mapping', status: :internal_server_error)
  end

  # PUT /api/v1/admin/reverse_proxy/url_mappings/:id
  def update
    mapping_id = params[:id]
    mapping_data = url_mapping_params
    
    AdminSetting.update_url_mapping(mapping_id, mapping_data)
    
    Rails.logger.info "URL mapping updated: #{mapping_id}"
    render_success({ message: 'URL mapping updated successfully' })
  rescue => e
    Rails.logger.error "Failed to update URL mapping: #{e.message}"
    render_error('Failed to update URL mapping', status: :internal_server_error)
  end

  # DELETE /api/v1/admin/reverse_proxy/url_mappings/:id
  def destroy
    mapping_id = params[:id]
    
    AdminSetting.remove_url_mapping(mapping_id)
    
    Rails.logger.info "URL mapping removed: #{mapping_id}"
    render_success({ message: 'URL mapping removed successfully' })
  rescue => e
    Rails.logger.error "Failed to remove URL mapping: #{e.message}"
    render_error('Failed to remove URL mapping', status: :internal_server_error)
  end

  # PATCH /api/v1/admin/reverse_proxy/url_mappings/:id/toggle
  def toggle
    mapping_id = params[:id]
    enabled = params[:enabled] == true || params[:enabled] == 'true'
    
    AdminSetting.toggle_url_mapping(mapping_id, enabled)
    
    Rails.logger.info "URL mapping #{enabled ? 'enabled' : 'disabled'}: #{mapping_id}"
    render_success({ message: "URL mapping #{enabled ? 'enabled' : 'disabled'} successfully" })
  rescue => e
    Rails.logger.error "Failed to toggle URL mapping: #{e.message}"
    render_error('Failed to toggle URL mapping', status: :internal_server_error)
  end

  private

  def require_system_admin_permission
    unless current_user.has_permission?('admin.settings.edit')
      render_error('Insufficient permissions to manage reverse proxy settings', status: :forbidden)
    end
  end

  def reverse_proxy_params
    params.require(:reverse_proxy_config).permit(
      :enabled, :current_environment,
      environments: {},
      url_mappings: [:id, :name, :pattern, :target_service, :priority, :enabled, :description, methods: []],
      load_balancing: [:enabled, :algorithm, :health_check_interval, :failover_enabled],
      ssl_config: [:enabled, :enforce_https, :certificate_path, :private_key_path, :hsts_enabled, :hsts_max_age, protocols: [], ciphers: []],
      cors_config: [:enabled, :credentials, :max_age, allowed_origins: [], allowed_methods: [], allowed_headers: [], exposed_headers: []],
      headers: {
        security_headers: [:enabled, :x_frame_options, :x_content_type_options, :x_xss_protection, :referrer_policy],
        custom_headers: {
          request: [:name, :value, :enabled],
          response: [:name, :value, :enabled]
        }
      },
      rate_limiting: [:enabled, :default_limit, :window_size, :burst_limit],
      compression: [:enabled, :level, types: []]
    )
  end

  def service_discovery_params
    params.require(:service_discovery_config).permit(
      :enabled, methods: [],
      dns_config: [:enabled, :timeout, :retries],
      consul_config: [:enabled, :host, :port, :token, :datacenter],
      port_scan_config: [:enabled, :timeout, port_ranges: {}],
      kubernetes_config: [:enabled, :namespace, :label_selector]
    )
  end

  def proxy_templates_params
    params.require(:proxy_templates).permit(
      nginx: [:enabled, :config_path, :reload_command, :test_command],
      apache: [:enabled, :config_path, :reload_command, :test_command],
      traefik: [:enabled, :config_path, :reload_command, :test_command]
    )
  end

  def url_mapping_params
    params.require(:url_mapping).permit(:name, :pattern, :target_service, :priority, :enabled, :description, methods: [])
  end

  def validate_proxy_config(config)
    errors = []
    
    # Validate basic structure
    errors << "Missing enabled field" unless config.key?('enabled')
    errors << "Missing environments configuration" unless config.key?('environments')
    errors << "Missing url_mappings configuration" unless config.key?('url_mappings')
    
    # Validate environments
    if config['environments']
      config['environments'].each do |env_name, env_config|
        env_config.each do |service_name, service_config|
          errors << "Missing host for #{service_name} in #{env_name}" unless service_config['host']
          errors << "Missing port for #{service_name} in #{env_name}" unless service_config['port']
          errors << "Missing protocol for #{service_name} in #{env_name}" unless service_config['protocol']
        end
      end
    end
    
    # Validate URL mappings
    if config['url_mappings']
      config['url_mappings'].each_with_index do |mapping, index|
        errors << "Missing pattern for mapping #{index + 1}" unless mapping['pattern']
        errors << "Missing target_service for mapping #{index + 1}" unless mapping['target_service']
        errors << "Invalid priority for mapping #{index + 1}" unless mapping['priority'].is_a?(Integer)
      end
    end
    
    {
      valid: errors.empty?,
      errors: errors
    }
  end

  def test_service_connectivity(config)
    environment = config['current_environment'] || Rails.env
    env_config = config.dig('environments', environment) || {}
    
    results = {}
    
    env_config.each do |service_name, service_config|
      begin
        health_url = "#{service_config['base_url']}#{service_config['health_check_path']}"
        start_time = Time.current
        
        uri = URI(health_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.open_timeout = 5
        http.read_timeout = 5
        
        response = http.get(uri.path)
        response_time = ((Time.current - start_time) * 1000).round(2)
        
        results[service_name] = {
          status: response.code == '200' ? 'healthy' : 'unhealthy',
          response_code: response.code.to_i,
          response_time_ms: response_time,
          url: health_url
        }
      rescue => e
        results[service_name] = {
          status: 'unreachable',
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
      # Powernode Reverse Proxy Configuration
      # Generated at: #{Time.current}
      
      upstream powernode_frontend {
    CONFIG

    # Add upstream definitions
    environment = config['current_environment'] || Rails.env
    env_config = config.dig('environments', environment) || {}
    
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
        
        # Security headers
    CONFIG

    if config.dig('headers', 'security_headers', 'enabled')
      headers = config.dig('headers', 'security_headers') || {}
      nginx_config += "    add_header X-Frame-Options #{headers['x_frame_options'] || 'SAMEORIGIN'} always;\n"
      nginx_config += "    add_header X-Content-Type-Options #{headers['x_content_type_options'] || 'nosniff'} always;\n"
      nginx_config += "    add_header X-XSS-Protection \"#{headers['x_xss_protection'] || '1; mode=block'}\" always;\n"
    end

    # Add location blocks for URL mappings
    sorted_mappings = (config['url_mappings'] || []).select { |m| m['enabled'] }.sort_by { |m| m['priority'] || 999 }
    
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
    when 'nginx'
      "1. Save configuration to /etc/nginx/sites-available/powernode\n2. Create symlink: sudo ln -s /etc/nginx/sites-available/powernode /etc/nginx/sites-enabled/\n3. Test configuration: sudo nginx -t\n4. Reload Nginx: sudo systemctl reload nginx"
    else
      "Installation instructions not available for #{proxy_type}"
    end
  end
end