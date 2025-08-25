# frozen_string_literal: true

module ReverseProxyConfiguration
  extend ActiveSupport::Concern

  module ClassMethods
    # Get reverse proxy configuration
    def reverse_proxy_config
      setting = find_by(key: 'reverse_proxy_config')
      return default_reverse_proxy_config unless setting
      
      parsed_value = setting.value.is_a?(String) ? JSON.parse(setting.value) : setting.value
      default_reverse_proxy_config.deep_merge(parsed_value)
    rescue JSON::ParserError
      default_reverse_proxy_config
    end

    # Get service discovery configuration  
    def service_discovery_config
      setting = find_by(key: 'service_discovery_config')
      return default_service_discovery_config unless setting
      
      parsed_value = setting.value.is_a?(String) ? JSON.parse(setting.value) : setting.value
      default_service_discovery_config.deep_merge(parsed_value)
    rescue JSON::ParserError
      default_service_discovery_config
    end

    # Get proxy templates configuration
    def proxy_templates
      setting = find_by(key: 'proxy_templates')
      return default_proxy_templates unless setting
      
      parsed_value = setting.value.is_a?(String) ? JSON.parse(setting.value) : setting.value
      default_proxy_templates.deep_merge(parsed_value)
    rescue JSON::ParserError
      default_proxy_templates
    end

    # Update reverse proxy configuration
    def update_reverse_proxy_config(new_config)
      setting = find_or_initialize_by(key: 'reverse_proxy_config')
      current_config = reverse_proxy_config
      merged_config = current_config.deep_merge(new_config.with_indifferent_access)
      setting.value = merged_config.to_json
      setting.description ||= 'Reverse proxy configuration for load balancing and routing'
      setting.save!
    end

    # Update service discovery configuration
    def update_service_discovery_config(new_config)
      setting = find_or_initialize_by(key: 'service_discovery_config')
      current_config = service_discovery_config
      merged_config = current_config.deep_merge(new_config.with_indifferent_access)
      setting.value = merged_config.to_json
      setting.description ||= 'Service discovery configuration for auto-detecting services'
      setting.save!
    end

    # Update proxy templates configuration
    def update_proxy_templates(new_config)
      setting = find_or_initialize_by(key: 'proxy_templates')
      current_config = proxy_templates
      merged_config = current_config.deep_merge(new_config.with_indifferent_access)
      setting.value = merged_config.to_json
      setting.description ||= 'Reverse proxy specific configuration templates'
      setting.save!
    end

    # Get current environment proxy configuration
    def current_environment_proxy_config(environment = nil)
      environment ||= Rails.env
      config = reverse_proxy_config
      config.dig('environments', environment) || {}
    end

    # Get service configuration for specific environment
    def service_config(service_name, environment = nil)
      environment ||= Rails.env
      current_environment_proxy_config(environment)[service_name] || {}
    end

    # Get URL mappings sorted by priority
    def sorted_url_mappings
      config = reverse_proxy_config
      mappings = config['url_mappings'] || []
      mappings.select { |mapping| mapping['enabled'] }.sort_by { |mapping| mapping['priority'] || 999 }
    end

    # Check if reverse proxy is enabled
    def reverse_proxy_enabled?
      reverse_proxy_config['enabled'] == true
    end

    # Get proxy health status
    def proxy_health_status
      config = reverse_proxy_config
      environment = config['current_environment'] || Rails.env
      env_config = config.dig('environments', environment) || {}
      
      status = {
        environment: environment,
        services: {},
        overall_status: 'healthy',
        last_checked: Time.current
      }

      env_config.each do |service_name, service_config|
        begin
          health_url = "#{service_config['base_url']}#{service_config['health_check_path']}"
          response = Net::HTTP.get_response(URI(health_url))
          
          status[:services][service_name] = {
            status: response.code == '200' ? 'healthy' : 'unhealthy',
            url: health_url,
            response_code: response.code,
            response_time: nil # Could add timing here
          }
        rescue => e
          status[:services][service_name] = {
            status: 'unreachable',
            url: health_url,
            error: e.message,
            response_time: nil
          }
          status[:overall_status] = 'degraded'
        end
      end

      status
    end

    # Update URL mapping by ID
    def update_url_mapping(mapping_id, mapping_data)
      config = reverse_proxy_config
      mappings = config['url_mappings'] || []
      
      mapping_index = mappings.find_index { |m| m['id'] == mapping_id }
      if mapping_index
        mappings[mapping_index] = mappings[mapping_index].merge(mapping_data)
      else
        mappings << mapping_data.merge('id' => mapping_id)
      end
      
      update_reverse_proxy_config('url_mappings' => mappings)
    end

    # Add new URL mapping
    def add_url_mapping(mapping_data)
      config = reverse_proxy_config
      mappings = config['url_mappings'] || []
      mappings << mapping_data
      update_reverse_proxy_config('url_mappings' => mappings)
    end

    # Remove URL mapping
    def remove_url_mapping(mapping_id)
      config = reverse_proxy_config
      mappings = config['url_mappings'] || []
      mappings.reject! { |m| m['id'] == mapping_id }
      update_reverse_proxy_config('url_mappings' => mappings)
    end

    # Enable/disable URL mapping
    def toggle_url_mapping(mapping_id, enabled)
      config = reverse_proxy_config
      mappings = config['url_mappings'] || []
      
      mapping = mappings.find { |m| m['id'] == mapping_id }
      if mapping
        mapping['enabled'] = enabled
        update_reverse_proxy_config('url_mappings' => mappings)
      end
    end

    private

    def default_reverse_proxy_config
      {
        'enabled' => false,
        'current_environment' => Rails.env,
        'environments' => {},
        'url_mappings' => [],
        'load_balancing' => { 
          'enabled' => false,
          'algorithm' => 'round_robin',
          'health_check_interval' => 30,
          'failover_enabled' => true
        },
        'ssl_config' => { 
          'enabled' => false,
          'enforce_https' => false,
          'certificate_path' => '/etc/ssl/certs/powernode.crt',
          'private_key_path' => '/etc/ssl/private/powernode.key',
          'protocols' => ['TLSv1.2', 'TLSv1.3'],
          'ciphers' => 'ECDHE+AESGCM:ECDHE+AES256:!aNULL:!MD5:!DSS',
          'hsts_enabled' => true,
          'hsts_max_age' => 31536000
        },
        'cors_config' => { 
          'enabled' => true,
          'allowed_origins' => ['*'],
          'allowed_methods' => ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
          'allowed_headers' => ['Content-Type', 'Authorization', 'X-Requested-With'],
          'exposed_headers' => [],
          'credentials' => true,
          'max_age' => 86400
        },
        'headers' => { 
          'security_headers' => { 
            'enabled' => true,
            'x_frame_options' => 'SAMEORIGIN',
            'x_content_type_options' => 'nosniff',
            'x_xss_protection' => '1; mode=block',
            'referrer_policy' => 'strict-origin-when-cross-origin'
          },
          'custom_headers' => {
            'request' => [],
            'response' => []
          }
        },
        'rate_limiting' => {
          'enabled' => false,
          'default_limit' => 1000,
          'window_size' => 3600,
          'burst_limit' => 100
        },
        'compression' => {
          'enabled' => true,
          'types' => ['text/html', 'text/css', 'text/javascript', 'application/json'],
          'level' => 6
        }
      }
    end

    def default_service_discovery_config
      {
        'enabled' => false,
        'methods' => [],
        'dns_config' => {
          'enabled' => true,
          'timeout' => 5,
          'retries' => 3
        },
        'consul_config' => {
          'enabled' => false,
          'host' => 'localhost',
          'port' => 8500,
          'token' => nil,
          'datacenter' => 'dc1'
        },
        'port_scan_config' => {
          'enabled' => false,
          'port_ranges' => {
            'frontend' => [3000, 3010],
            'backend' => [5000, 5010],
            'worker' => [6000, 6010]
          },
          'timeout' => 5
        },
        'kubernetes_config' => {
          'enabled' => false,
          'namespace' => 'default',
          'label_selector' => 'app=service'
        }
      }
    end

    def default_proxy_templates
      {
        'nginx' => { 'enabled' => false },
        'apache' => { 'enabled' => false },
        'traefik' => { 'enabled' => false }
      }
    end
  end
end