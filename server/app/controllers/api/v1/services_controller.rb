# frozen_string_literal: true

class Api::V1::ServicesController < ApplicationController
  before_action :authenticate_request
  before_action :require_system_admin_permission

  # Worker job classes - load dynamically to avoid circular dependencies
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
    render_success(proxy_service.get_full_config)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch services config: #{e.message}"
    render_error("Failed to fetch services configuration", status: :internal_server_error)
  end

  # PUT /api/v1/admin/reverse_proxy
  def update
    config_type = params[:config_type] || "service_config"
    config_params = case config_type
                    when "service_config" then service_config_params.to_h
                    when "service_discovery_config" then service_discovery_params.to_h
                    when "service_templates" then service_templates_params.to_h
                    else
                      return render_error("Invalid configuration type", status: :bad_request)
                    end

    result = proxy_service.update_config(config_type: config_type, config_params: config_params)

    if result.success?
      Rails.logger.info "Services config updated by user #{current_user.email}"
      render_success(result.data)
    else
      render_error(result.error, status: :internal_server_error)
    end
  end

  # POST /api/v1/admin/reverse_proxy/test
  def test_configuration
    test_config = params[:test_config] || AdminSetting.reverse_proxy_config

    validation_result = proxy_service.validate_config(test_config)
    unless validation_result[:valid]
      return render_error("Configuration validation failed: #{validation_result[:errors].join(', ')}", status: :unprocessable_content)
    end

    result = enqueue_job(:test_configuration, test_config, "services_test_configuration", { test_config: test_config })
    result ? render_success(result) : render_error("Test configuration worker not available", status: :service_unavailable)
  rescue StandardError => e
    Rails.logger.error "Failed to start configuration test: #{e.message}"
    render_error("Failed to start configuration test", status: :internal_server_error)
  end

  # POST /api/v1/admin/reverse_proxy/generate_config
  def generate_config
    proxy_type = params[:proxy_type] || "nginx"
    config = AdminSetting.reverse_proxy_config

    unless proxy_service.valid_proxy_type?(proxy_type)
      return render_error("Unsupported proxy type: #{proxy_type}. Valid types: nginx, apache, traefik", status: :bad_request)
    end

    result = enqueue_job(:generate_config, [proxy_type, config], "services_generate_config", { proxy_type: proxy_type, config_size: config.to_s.length })

    if result
      render_success(result.merge(proxy_type: proxy_type, message: "#{proxy_type.capitalize} configuration generation started. Use job_id to check progress."))
    else
      render_error("Config generation worker not available", status: :service_unavailable)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to start config generation: #{e.message}"
    render_error("Failed to start config generation", status: :internal_server_error)
  end

  # GET /api/v1/admin/reverse_proxy/health
  def health_check
    render_success(AdminSetting.proxy_health_status)
  rescue StandardError => e
    Rails.logger.error "Health check failed: #{e.message}"
    render_error("Health check failed", status: :internal_server_error)
  end

  # GET /api/v1/admin/reverse_proxy/status
  def status
    render_success(proxy_service.get_status)
  rescue StandardError => e
    Rails.logger.error "Status check failed: #{e.message}"
    render_error("Status check failed", status: :internal_server_error)
  end

  # POST /api/v1/admin/reverse_proxy/url_mappings
  def create
    mapping = proxy_service.create_url_mapping(url_mapping_params.to_h)
    Rails.logger.info "URL mapping created: #{mapping['pattern']} -> #{mapping['target_service']}"
    render_success(message: "URL mapping created successfully", mapping: mapping)
  rescue StandardError => e
    Rails.logger.error "Failed to create URL mapping: #{e.message}"
    render_error("Failed to create URL mapping", status: :internal_server_error)
  end

  # PUT /api/v1/admin/reverse_proxy/url_mappings/:id
  def update_url_mapping
    proxy_service.update_url_mapping(params[:id], url_mapping_params.to_h)
    Rails.logger.info "URL mapping updated: #{params[:id]}"
    render_success(message: "URL mapping updated successfully")
  rescue StandardError => e
    Rails.logger.error "Failed to update URL mapping: #{e.message}"
    render_error("Failed to update URL mapping", status: :internal_server_error)
  end

  # DELETE /api/v1/admin/reverse_proxy/url_mappings/:id
  def destroy
    proxy_service.remove_url_mapping(params[:id])
    Rails.logger.info "URL mapping removed: #{params[:id]}"
    render_success(message: "URL mapping removed successfully")
  rescue StandardError => e
    Rails.logger.error "Failed to remove URL mapping: #{e.message}"
    render_error("Failed to remove URL mapping", status: :internal_server_error)
  end

  # PATCH /api/v1/admin/reverse_proxy/url_mappings/:id/toggle
  def toggle
    enabled = params[:enabled] == true || params[:enabled] == "true"
    proxy_service.toggle_url_mapping(params[:id], enabled)
    Rails.logger.info "URL mapping #{enabled ? 'enabled' : 'disabled'}: #{params[:id]}"
    render_success(message: "URL mapping #{enabled ? 'enabled' : 'disabled'} successfully")
  rescue StandardError => e
    Rails.logger.error "Failed to toggle URL mapping: #{e.message}"
    render_error("Failed to toggle URL mapping", status: :internal_server_error)
  end

  # GET /api/v1/admin/reverse_proxy/discovered_services
  def discovered_services
    render_success(proxy_service.discovered_services)
  rescue StandardError => e
    Rails.logger.error "Failed to get discovered services: #{e.message}"
    render_error("Failed to retrieve discovered services", status: :internal_server_error)
  end

  # POST /api/v1/admin/reverse_proxy/service_discovery
  def service_discovery
    config = AdminSetting.service_discovery_config
    return render_error("Service discovery is not enabled", status: :unprocessable_content) unless config["enabled"]

    result = enqueue_job(:service_discovery, config, "services_service_discovery", { methods: config["methods"], enabled_methods_count: config["methods"]&.length || 0 })

    if result
      render_success(result.merge(methods: config["methods"], message: "Service discovery started. Use job_id to check progress and results."))
    else
      render_error("Service discovery worker not available", status: :service_unavailable)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to start service discovery: #{e.message}"
    render_error("Failed to start service discovery", status: :internal_server_error)
  end

  # POST /api/v1/admin/reverse_proxy/add_discovered_service
  def add_discovered_service
    service_data = params.require(:service).permit(:name, :host, :port, :protocol, :health_check_path)
    result = proxy_service.add_service(service_data.to_h.symbolize_keys)

    if result.success?
      render_success(result.data)
    else
      render_error(result.error, status: :internal_server_error)
    end
  end

  # GET /api/v1/admin/reverse_proxy/health_history/:service_name
  def health_history
    hours = params[:hours]&.to_i || 24
    render_success(proxy_service.health_history(service_name: params[:service_name], hours: hours))
  rescue StandardError => e
    Rails.logger.error "Failed to get health history: #{e.message}"
    render_error("Failed to retrieve health history", status: :internal_server_error)
  end

  # PUT /api/v1/admin/reverse_proxy/health_config/:service_name
  def update_health_config
    params.require(:health_config).permit(:interval, :timeout, :health_check_path, expected_codes: [])
    render_success(message: "Health check configuration updated for #{params[:service_name]}")
  rescue StandardError => e
    Rails.logger.error "Failed to update health config: #{e.message}"
    render_error("Failed to update health check configuration", status: :internal_server_error)
  end

  # POST /api/v1/admin/reverse_proxy/test_service
  def test_service
    result = proxy_service.test_service(environment: params[:environment], service_name: params[:service_name])

    if result[:status] == "not_found"
      render_error(result[:error], status: :not_found)
    else
      render_success(result)
    end
  end

  # POST /api/v1/admin/reverse_proxy/validate_service
  def validate_service
    service_config = params.require(:service_config).permit(:host, :port, :protocol, :health_check_path)
    render_success(proxy_service.validate_service(service_config.to_h.symbolize_keys))
  end

  # GET /api/v1/admin/reverse_proxy/service_templates
  def service_templates
    render_success(proxy_service.service_templates)
  end

  # POST /api/v1/admin/reverse_proxy/duplicate_service
  def duplicate_service
    result = proxy_service.duplicate_service(
      environment: params[:environment],
      service_name: params[:service_name],
      new_name: params[:new_name]
    )

    if result.success?
      render_success(result.data)
    else
      status = result.error.include?("not found") ? :not_found : :unprocessable_content
      render_error(result.error, status: status)
    end
  end

  # GET /api/v1/admin/reverse_proxy/export_services/:environment
  def export_services
    render_success(proxy_service.export_services(params[:environment]))
  end

  # POST /api/v1/admin/reverse_proxy/import_services
  def import_services
    result = proxy_service.import_services(
      environment: params[:environment],
      import_services: params[:services]&.to_unsafe_h || {}
    )
    render_success(result)
  rescue StandardError => e
    Rails.logger.error "Failed to import services: #{e.message}"
    render_error("Failed to import services", status: :internal_server_error)
  end

  private

  def proxy_service
    @proxy_service ||= ::Services::ProxyConfigService.new
  end

  def require_system_admin_permission
    unless current_user.has_permission?("admin.settings.update")
      render_error("Insufficient permissions to manage services settings", status: :forbidden)
    end
  end

  def enqueue_job(job_type, job_args, job_name, metadata)
    job_id = SecureRandom.uuid
    job_class = get_job_class(job_type)
    return nil unless job_class

    args = job_args.is_a?(Array) ? job_args + [{ job_id: job_id }] : [job_args, { job_id: job_id }]
    sidekiq_jid = job_class.perform_async(*args)
    BackgroundJob.create_for_sidekiq_job(sidekiq_jid, job_name, metadata)

    { job_id: job_id, sidekiq_jid: sidekiq_jid, status: "started" }
  end

  def service_config_params
    params.require(:service_config).permit(
      :enabled, :current_environment, environments: {},
      url_mappings: [:id, :name, :pattern, :target_service, :priority, :enabled, :description, methods: []],
      load_balancing: [:enabled, :algorithm, :health_check_interval, :failover_enabled],
      ssl_config: [:enabled, :enforce_https, :certificate_path, :private_key_path, :hsts_enabled, :hsts_max_age, :ciphers, protocols: []],
      cors_config: [:enabled, :credentials, :max_age, allowed_origins: [], allowed_methods: [], allowed_headers: [], exposed_headers: []],
      headers: { security_headers: [:enabled, :x_frame_options, :x_content_type_options, :x_xss_protection, :referrer_policy], custom_headers: { request: [:name, :value, :enabled], response: [:name, :value, :enabled] } },
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

  def service_templates_params
    params.require(:service_templates).permit(
      nginx: [:enabled, :config_path, :reload_command, :test_command],
      apache: [:enabled, :config_path, :reload_command, :test_command],
      traefik: [:enabled, :config_path, :reload_command, :test_command]
    )
  end

  def url_mapping_params
    params.require(:url_mapping).permit(:name, :pattern, :target_service, :priority, :enabled, :description, methods: [])
  end
end
