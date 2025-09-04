# frozen_string_literal: true

module ServiceConfiguration
  extend ActiveSupport::Concern

  module ClassMethods
    # Get services configuration
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

    # Get service templates configuration
    def service_templates
      setting = find_by(key: 'service_templates')
      return default_service_templates unless setting
      
      parsed_value = setting.value.is_a?(String) ? JSON.parse(setting.value) : setting.value
      default_service_templates.deep_merge(parsed_value)
    rescue JSON::ParserError
      default_service_templates
    end

    # Update services configuration
    def update_reverse_proxy_config(new_config)
      setting = find_or_initialize_by(key: 'reverse_proxy_config')
      current_config = reverse_proxy_config
      merged_config = current_config.deep_merge(new_config.with_indifferent_access)
      setting.value = merged_config.to_json
      # No description field in AdminSetting model
      setting.save!
    end

    # Update service discovery configuration
    def update_service_discovery_config(new_config)
      setting = find_or_initialize_by(key: 'service_discovery_config')
      current_config = service_discovery_config
      merged_config = current_config.deep_merge(new_config.with_indifferent_access)
      setting.value = merged_config.to_json
      # No description field in AdminSetting model
      setting.save!
    end

    # Update service templates configuration
    def update_service_templates(new_config)
      setting = find_or_initialize_by(key: 'service_templates')
      current_config = service_templates
      merged_config = current_config.deep_merge(new_config.with_indifferent_access)
      setting.value = merged_config.to_json
      # No description field in AdminSetting model
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

    # Check if services are enabled
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

    # Reverse Proxy URL Configuration Methods
    
    # Get reverse proxy URL configuration
    def reverse_proxy_url_config
      setting = find_by(key: 'reverse_proxy_url_config')
      return default_reverse_proxy_url_config unless setting
      
      parsed_value = setting.value.is_a?(String) ? JSON.parse(setting.value) : setting.value
      default_reverse_proxy_url_config.deep_merge(parsed_value)
    rescue JSON::ParserError
      default_reverse_proxy_url_config
    end
    
    # Update reverse proxy URL configuration
    def update_reverse_proxy_url_config(new_config)
      setting = find_or_initialize_by(key: 'reverse_proxy_url_config')
      current_config = reverse_proxy_url_config
      
      # Deep merge with special handling for arrays (replace instead of merge)
      merged_config = current_config.deep_merge(new_config.with_indifferent_access) do |key, old_val, new_val|
        # For arrays, replace instead of merge
        if old_val.is_a?(Array) && new_val.is_a?(Array)
          new_val
        else
          new_val
        end
      end
      
      setting.value = merged_config.to_json
      setting.save!
      merged_config
    end
    
    # Validate proxy host against trusted patterns
    def validate_proxy_host(host)
      config = reverse_proxy_url_config
      return { valid: false, trusted: false, errors: ['Proxy URL configuration not enabled'] } unless config[:enabled]
      
      errors = []
      suspicious = false
      
      # Check for suspicious patterns
      suspicious_patterns = [
        /javascript:/i,
        /data:text\/html/i,
        /<script/i,
        /onclick=/i,
        /onerror=/i
      ]
      
      suspicious_patterns.each do |pattern|
        if host.match?(pattern)
          suspicious = true
          errors << "Host contains suspicious pattern: #{pattern.source}"
        end
      end
      
      # Skip RFC validation for wildcard patterns, but validate them differently
      if host.include?('*')
        unless valid_wildcard_pattern?(host)
          errors << "Invalid wildcard pattern: '#{host}'"
        end
      else
        # Validate RFC-compliant hostname format for non-wildcard hosts
        unless valid_hostname_format?(host)
          errors << "Host '#{host}' is not RFC-compliant"
        end
      end
      
      # Check if host is trusted
      trusted = host_in_trusted_list?(host, config[:trusted_hosts] || [])
      
      if config.dig(:security, :strict_mode) && !trusted
        errors << "Host '#{host}' is not in trusted hosts list"
      end
      
      {
        valid: errors.empty? && !suspicious,
        trusted: trusted,
        suspicious: suspicious,
        errors: errors
      }
    end
    
    # Generate API URLs based on proxy context
    def generate_api_url(proxy_context = {})
      config = reverse_proxy_url_config
      
      # Use proxy-provided values or fall back to defaults
      proto = proxy_context[:forwarded_proto] || config[:default_protocol] || 'https'
      host = proxy_context[:forwarded_host] || config[:default_host] || request_host
      port = proxy_context[:forwarded_port] || config[:default_port]
      path = proxy_context[:forwarded_path] || config[:base_path] || ''
      
      # Build base URL
      base_url = "#{proto}://#{host}"
      base_url += ":#{port}" if port && !default_port?(proto, port)
      base_url += path unless path.empty?
      
      # Generate URL collection for client
      {
        base_url: base_url,
        api_url: "#{base_url}/api/v1",
        websocket_url: websocket_url_from_base(base_url),
        frontend_url: frontend_url_from_base(base_url),
        generated_at: Time.current.iso8601,
        proxy_detected: proxy_context.any?
      }
    end
    
    # Add trusted host pattern
    def add_trusted_host(pattern)
      config = reverse_proxy_url_config
      trusted_hosts = config[:trusted_hosts] || []
      
      unless trusted_hosts.include?(pattern)
        trusted_hosts << pattern
        update_reverse_proxy_url_config(trusted_hosts: trusted_hosts)
      end
      
      true
    end
    
    # Remove trusted host pattern
    def remove_trusted_host(pattern)
      config = reverse_proxy_url_config
      trusted_hosts = config[:trusted_hosts] || []
      
      if trusted_hosts.include?(pattern)
        trusted_hosts.delete(pattern)
        update_reverse_proxy_url_config(trusted_hosts: trusted_hosts)
      end
      
      true
    end
    
    # Test proxy headers simulation
    def test_proxy_headers(headers)
      proxy_context = {
        forwarded_host: headers['X-Forwarded-Host'],
        forwarded_proto: headers['X-Forwarded-Proto'],
        forwarded_port: headers['X-Forwarded-Port'],
        forwarded_path: headers['X-Forwarded-Path']
      }.compact
      
      validation = validate_proxy_host(proxy_context[:forwarded_host]) if proxy_context[:forwarded_host]
      generated_urls = generate_api_url(proxy_context)
      
      {
        proxy_context: proxy_context,
        validation: validation,
        generated_urls: generated_urls,
        test_performed_at: Time.current.iso8601
      }
    end
    
    private
    
    def host_in_trusted_list?(host, trusted_hosts)
      trusted_hosts.any? do |pattern|
        if pattern.include?('*')
          # Convert wildcard pattern to regex
          regex_pattern = pattern.gsub('.', '\.').gsub('*', '.*')
          host.match?(/^#{regex_pattern}$/i)
        else
          host.downcase == pattern.downcase
        end
      end
    end
    
    def valid_hostname_format?(hostname)
      return false if hostname.nil? || hostname.empty?
      
      # Remove port if present
      host = hostname.split(':').first
      
      # RFC 1123 compliant hostname validation
      return false if host.length > 253
      
      labels = host.split('.')
      labels.all? do |label|
        label.length.between?(1, 63) &&
          label.match?(/^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$/i)
      end
    end
    
    def valid_wildcard_pattern?(pattern)
      return false if pattern.nil? || pattern.empty?
      
      # Remove port if present
      host = pattern.split(':').first
      
      # Wildcard patterns should only have * at the beginning of a label
      # Valid: *.example.com, *.subdomain.example.com
      # Invalid: example.*.com, *example.com, example*.com
      return false unless host.match?(/\A\*\.[a-z0-9\-.]+\z/i)
      
      # Validate the non-wildcard part
      non_wildcard_part = host.sub(/\A\*\./, '')
      
      # The rest should be a valid domain
      return false if non_wildcard_part.length > 253
      
      labels = non_wildcard_part.split('.')
      return false if labels.length < 2 # Need at least domain.tld
      
      labels.all? do |label|
        label.length.between?(1, 63) &&
          label.match?(/^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$/i)
      end
    end
    
    def default_port?(proto, port)
      (proto == 'http' && port.to_i == 80) ||
        (proto == 'https' && port.to_i == 443)
    end
    
    def websocket_url_from_base(base_url)
      base_url.gsub(/^http/, 'ws')
    end
    
    def frontend_url_from_base(base_url)
      # Frontend is typically at the same base URL
      base_url
    end
    
    def request_host
      # Fallback to request host if available
      defined?(request) ? request.host : 'localhost'
    end
    
    def default_reverse_proxy_url_config
      {
        enabled: false,
        trusted_hosts: ['localhost', '127.0.0.1', '::1'],
        default_protocol: 'https',
        default_host: nil,
        default_port: nil,
        base_path: '',
        security: {
          enabled: true,
          strict_mode: false,
          validate_host_format: true,
          block_suspicious_patterns: true
        },
        multi_tenancy: {
          enabled: false,
          wildcard_patterns: []
        }
      }.with_indifferent_access
    end

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

    def default_service_templates
      {
        'nginx' => { 'enabled' => false },
        'apache' => { 'enabled' => false },
        'traefik' => { 'enabled' => false }
      }
    end
  end
end