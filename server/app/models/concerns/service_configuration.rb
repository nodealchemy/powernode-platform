# frozen_string_literal: true

module ServiceConfiguration
  extend ActiveSupport::Concern

  module ClassMethods
    # Reverse Proxy URL Configuration Methods

    # Get reverse proxy URL configuration
    def reverse_proxy_url_config
      setting = find_by(key: "reverse_proxy_url_config")
      return default_reverse_proxy_url_config unless setting

      parsed_value = setting.value.is_a?(String) ? JSON.parse(setting.value) : setting.value
      default_reverse_proxy_url_config.deep_merge(parsed_value)
    rescue JSON::ParserError
      default_reverse_proxy_url_config
    end

    # Update reverse proxy URL configuration
    def update_reverse_proxy_url_config(new_config)
      setting = find_or_initialize_by(key: "reverse_proxy_url_config")
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
      return { valid: false, trusted: false, errors: [ "Proxy URL configuration not enabled" ] } unless config[:enabled]

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
      if host.include?("*")
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
      proto = proxy_context[:forwarded_proto] || config[:default_protocol] || "https"
      host = proxy_context[:forwarded_host] || config[:default_host] || request_host
      port = proxy_context[:forwarded_port] || config[:default_port]
      path = proxy_context[:forwarded_path] || config[:base_path] || ""

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

    # Resolve the frontend URL from an incoming request.
    # Uses the request's own origin and checks trusted hosts for a matching
    # frontend port (e.g., host:3001 paired with host:3000). Behind a reverse
    # proxy where both services share one hostname, returns the same origin.
    def frontend_url_for_request(request)
      forwarded_host = request.headers["X-Forwarded-Host"]
      proto = request.headers["X-Forwarded-Proto"] || request.scheme
      host = forwarded_host || request.host

      # Strip port from hostname for matching (IPv6 addresses preserved)
      bare_host = host.include?(":") && !host.start_with?(":") && host.match?(/:\d+\z/) ?
        host.sub(/:\d+\z/, "") : host

      # Look for a different-port entry for the same hostname in trusted hosts
      # (e.g., dev.example.test:3001 paired with dev.example.test:3000)
      config = reverse_proxy_url_config
      trusted = config[:trusted_hosts] || []
      backend_port = request.headers["X-Forwarded-Port"]&.to_i || request.port

      frontend_entry = trusted.find do |entry|
        next false unless entry.include?(":")
        entry_host, entry_port = entry.rpartition(":").values_at(0, 2)
        entry_host == bare_host && entry_port.to_i != backend_port
      end

      if frontend_entry
        fe_host, _, fe_port = frontend_entry.rpartition(":")
        url = "#{proto}://#{fe_host}"
        url += ":#{fe_port}" unless default_port?(proto, fe_port)
        url
      else
        # Same-origin setup (reverse proxy): frontend is at the same base URL
        url = "#{proto}://#{host}"
        port = request.headers["X-Forwarded-Port"] || request.port.to_s
        url += ":#{port}" unless default_port?(proto, port)

        # Split-origin deployments (e.g. dev: the SPA runs on a different port
        # than the API) set FRONTEND_URL explicitly. Honor it when it points at
        # a different origin than this request — otherwise the OAuth consent
        # redirect loops back to the API host, which serves no SPA routes.
        explicit = ENV["FRONTEND_URL"].presence&.chomp("/")
        return explicit if explicit && explicit != url

        url
      end
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
        forwarded_host: headers["X-Forwarded-Host"],
        forwarded_proto: headers["X-Forwarded-Proto"],
        forwarded_port: headers["X-Forwarded-Port"],
        forwarded_path: headers["X-Forwarded-Path"]
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

    # =============================================================================
    # REDIS CONFIGURATION
    # =============================================================================

    # Get Redis configuration
    def redis_config
      setting = find_by(key: "redis_config")
      return default_redis_config unless setting

      parsed_value = setting.value.is_a?(String) ? JSON.parse(setting.value) : setting.value
      default_redis_config.deep_merge(parsed_value)
    rescue JSON::ParserError
      default_redis_config
    end

    # Update Redis configuration
    def update_redis_config(new_config)
      setting = find_or_initialize_by(key: "redis_config")
      current_config = redis_config
      merged_config = current_config.deep_merge(new_config.with_indifferent_access)
      setting.value = merged_config.to_json
      setting.save!
    end

    # Build redis:// URL from config components
    def redis_url_from_config(config = nil)
      config ||= redis_config

      # If explicit URL is set, use it directly
      return config["url"] if config["url"].present?

      # Build URL from components
      host = config["host"] || "localhost"
      port = config["port"] || 6379
      database = config["database"] || 0
      password = config["password"]
      ssl = config["ssl"]

      scheme = ssl ? "rediss" : "redis"
      auth = password.present? ? ":#{password}@" : ""
      "#{scheme}://#{auth}#{host}:#{port}/#{database}"
    end

    # Test Redis connection with optional config override
    def test_redis_connection(config = nil)
      config ||= redis_config
      url = redis_url_from_config(config)

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      redis = ::Redis.new(url: url, connect_timeout: 5, read_timeout: 5)
      redis.ping
      latency = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)

      info = redis.info
      {
        status: "connected",
        version: info["redis_version"],
        memory: info["used_memory_human"],
        latency_ms: latency,
        connected_clients: info["connected_clients"]&.to_i || 0
      }
    rescue StandardError => e
      {
        status: "disconnected",
        error: e.message
      }
    ensure
      redis&.close rescue nil
    end

    private

    def default_redis_config
      {
        "host" => ENV.fetch("REDIS_HOST", "localhost"),
        "port" => ENV.fetch("REDIS_PORT", 6379).to_i,
        "database" => ENV.fetch("REDIS_DB", 0).to_i,
        "password" => ENV.fetch("REDIS_PASSWORD", nil),
        "ssl" => false,
        "url" => ENV.fetch("REDIS_URL", nil),
        "connect_timeout" => 5,
        "read_timeout" => 5,
        "write_timeout" => 5,
        "pool_size" => 5
      }
    end

    def host_in_trusted_list?(host, trusted_hosts)
      trusted_hosts.any? do |pattern|
        if pattern.include?("*")
          # Convert wildcard pattern to regex
          regex_pattern = pattern.gsub(".", '\.').gsub("*", ".*")
          host.match?(/^#{regex_pattern}$/i)
        else
          host.downcase == pattern.downcase
        end
      end
    end

    def valid_hostname_format?(hostname)
      return false if hostname.nil? || hostname.empty?

      # Remove port if present
      host = hostname.split(":").first

      # RFC 1123 compliant hostname validation
      return false if host.length > 253

      labels = host.split(".")
      labels.all? do |label|
        label.length.between?(1, 63) &&
          label.match?(/^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$/i)
      end
    end

    def valid_wildcard_pattern?(pattern)
      return false if pattern.nil? || pattern.empty?

      # Remove port if present
      host = pattern.split(":").first

      # Wildcard patterns should only have * at the beginning of a label
      # Valid: *.example.com, *.subdomain.example.com
      # Invalid: example.*.com, *example.com, example*.com
      return false unless host.match?(/\A\*\.[a-z0-9\-.]+\z/i)

      # Validate the non-wildcard part
      non_wildcard_part = host.sub(/\A\*\./, "")

      # The rest should be a valid domain
      return false if non_wildcard_part.length > 253

      labels = non_wildcard_part.split(".")
      return false if labels.length < 2 # Need at least domain.tld

      labels.all? do |label|
        label.length.between?(1, 63) &&
          label.match?(/^[a-z0-9]([a-z0-9\-]{0,61}[a-z0-9])?$/i)
      end
    end

    def default_port?(proto, port)
      (proto == "http" && port.to_i == 80) ||
        (proto == "https" && port.to_i == 443)
    end

    def websocket_url_from_base(base_url)
      base_url.gsub(/^http/, "ws")
    end

    def frontend_url_from_base(base_url)
      # Frontend is typically at the same base URL
      base_url
    end

    def request_host
      # Fallback to request host if available
      defined?(request) ? request.host : "localhost"
    end

    def default_reverse_proxy_url_config
      {
        enabled: false,
        trusted_hosts: [ "localhost", "127.0.0.1", "::1" ],
        default_protocol: "https",
        default_host: nil,
        default_port: nil,
        base_path: "",
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
  end
end
