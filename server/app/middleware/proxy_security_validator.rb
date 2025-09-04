# frozen_string_literal: true

# Middleware for validating and processing reverse proxy headers
class ProxySecurityValidator
  PROXY_HEADERS = %w[
    HTTP_X_FORWARDED_HOST
    HTTP_X_FORWARDED_PROTO
    HTTP_X_FORWARDED_PORT
    HTTP_X_FORWARDED_PATH
    HTTP_X_FORWARDED_FOR
    HTTP_X_REAL_IP
  ].freeze

  SUSPICIOUS_PATTERNS = [
    /javascript:/i,
    /data:text\/html/i,
    /<script/i,
    /onclick=/i,
    /onerror=/i
  ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    # Extract proxy context from headers
    proxy_context = extract_proxy_context(env)
    
    # Validate proxy headers if proxy detection is enabled
    if proxy_settings_enabled?
      validation_result = validate_proxy_headers(proxy_context)
      
      # Block request if strict mode is enabled and validation fails
      if strict_mode_enabled? && !validation_result[:valid]
        return [
          403,
          { 'Content-Type' => 'application/json' },
          [{ error: 'Invalid proxy headers', details: validation_result[:errors] }.to_json]
        ]
      end
      
      # Add security headers for proxy-aware responses
      env['proxy.context'] = proxy_context
      env['proxy.validation'] = validation_result
      
      # Log suspicious patterns
      log_suspicious_activity(env, proxy_context) if validation_result[:suspicious]
    end
    
    # Continue with request processing
    status, headers, response = @app.call(env)
    
    # Add security headers to response
    headers = add_security_headers(headers, proxy_context) if proxy_settings_enabled?
    
    [status, headers, response]
  rescue StandardError => e
    Rails.logger.error "ProxySecurityValidator error: #{e.message}"
    @app.call(env)
  end

  private

  def extract_proxy_context(env)
    {
      forwarded_host: env['HTTP_X_FORWARDED_HOST'],
      forwarded_proto: env['HTTP_X_FORWARDED_PROTO'],
      forwarded_port: env['HTTP_X_FORWARDED_PORT'],
      forwarded_path: env['HTTP_X_FORWARDED_PATH'],
      forwarded_for: env['HTTP_X_FORWARDED_FOR'],
      real_ip: env['HTTP_X_REAL_IP'],
      original_host: env['HTTP_HOST'],
      detected_at: Time.current
    }.compact
  end

  def validate_proxy_headers(proxy_context)
    errors = []
    suspicious = false
    
    # Validate host header format
    if proxy_context[:forwarded_host]
      host = proxy_context[:forwarded_host]
      
      # Check for suspicious patterns
      SUSPICIOUS_PATTERNS.each do |pattern|
        if host.match?(pattern)
          suspicious = true
          errors << "Host contains suspicious pattern: #{pattern.source}"
        end
      end
      
      # Validate against trusted hosts
      unless host_trusted?(host)
        errors << "Host '#{host}' is not in trusted hosts list"
      end
      
      # Validate RFC-compliant hostname format
      unless valid_hostname_format?(host)
        errors << "Host '#{host}' is not RFC-compliant"
      end
    end
    
    # Validate protocol
    if proxy_context[:forwarded_proto]
      unless %w[http https ws wss].include?(proxy_context[:forwarded_proto].downcase)
        errors << "Invalid protocol: #{proxy_context[:forwarded_proto]}"
      end
    end
    
    # Validate port
    if proxy_context[:forwarded_port]
      port = proxy_context[:forwarded_port].to_i
      unless port.between?(1, 65535)
        errors << "Invalid port: #{proxy_context[:forwarded_port]}"
      end
    end
    
    {
      valid: errors.empty?,
      suspicious: suspicious,
      errors: errors,
      trusted: host_trusted?(proxy_context[:forwarded_host])
    }
  end

  def host_trusted?(host)
    return true unless host
    
    trusted_hosts = proxy_settings[:trusted_hosts] || []
    
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
    # - Maximum 253 characters
    # - Labels up to 63 characters
    # - Alphanumeric and hyphens only
    # - Cannot start or end with hyphen
    return false if host.length > 253
    
    labels = host.split('.')
    labels.all? do |label|
      label.length.between?(1, 63) &&
        label.match?(/^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$/i)
    end
  end

  def add_security_headers(headers, proxy_context)
    headers = headers.dup
    
    # Add proxy detection headers for client awareness
    if proxy_context.any?
      headers['X-Proxy-Detected'] = 'true'
      headers['X-Original-Host'] = proxy_context[:original_host] if proxy_context[:original_host]
    end
    
    # Add security headers
    headers['X-Content-Type-Options'] = 'nosniff'
    headers['X-Frame-Options'] = 'SAMEORIGIN'
    headers['X-XSS-Protection'] = '1; mode=block'
    headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    
    # Add CSP header with proxy-aware origins
    if proxy_context[:forwarded_host]
      proto = proxy_context[:forwarded_proto] || 'https'
      origin = "#{proto}://#{proxy_context[:forwarded_host]}"
      headers['Content-Security-Policy'] = "default-src 'self' #{origin}"
    end
    
    headers
  end

  def log_suspicious_activity(env, proxy_context)
    Rails.logger.warn({
      event: 'suspicious_proxy_headers',
      ip: env['REMOTE_ADDR'],
      proxy_context: proxy_context,
      user_agent: env['HTTP_USER_AGENT'],
      path: env['PATH_INFO'],
      timestamp: Time.current.iso8601
    }.to_json)
    
    # Create audit log entry if available
    if defined?(AuditLog)
      AuditLog.create(
        action: 'proxy.suspicious_headers',
        source: 'ProxySecurityValidator',
        ip_address: env['REMOTE_ADDR'],
        user_agent: env['HTTP_USER_AGENT'],
        metadata: {
          proxy_context: proxy_context,
          path: env['PATH_INFO']
        }
      )
    end
  end

  def proxy_settings
    @proxy_settings ||= begin
      if defined?(AdminSetting)
        AdminSetting.get_value('reverse_proxy_url_config') || {}
      else
        {}
      end
    rescue StandardError => e
      Rails.logger.error "Failed to load proxy settings: #{e.message}"
      {}
    end
  end

  def proxy_settings_enabled?
    proxy_settings[:enabled] == true
  end

  def strict_mode_enabled?
    proxy_settings.dig(:security, :strict_mode) == true
  end
end