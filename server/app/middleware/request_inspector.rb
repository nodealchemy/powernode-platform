# frozen_string_literal: true

# Request Inspector Middleware for DDoS Protection
# Analyzes incoming requests for suspicious patterns and potential attacks

class RequestInspector
  # =========================================================================
  # CONFIGURATION
  # =========================================================================

  # Suspicious patterns that indicate potential attacks
  SUSPICIOUS_PATTERNS = {
    # SQL Injection patterns
    sql_injection: [
      /(\bUNION\b.*\bSELECT\b|\bSELECT\b.*\bFROM\b)/i,
      /(\bDROP\b.*\bTABLE\b|\bDELETE\b.*\bFROM\b)/i,
      /(\bINSERT\b.*\bINTO\b|\bUPDATE\b.*\bSET\b)/i,
      /(\b1\s*=\s*1\b|\b1\s*=\s*'1'\b)/i,
      /(\bOR\b\s+\d+\s*=\s*\d+|\bAND\b\s+\d+\s*=\s*\d+)/i
    ],

    # XSS patterns
    xss: [
      /<script\b[^>]*>/i,
      /javascript:/i,
      /on\w+\s*=/i,
      /<iframe\b[^>]*>/i,
      /document\.(cookie|location|write)/i
    ],

    # Path traversal
    path_traversal: [
      /\.\.\//,
      /\.\.%2[Ff]/i,
      /%2e%2e%2f/i,
      /\.\.\\/, # Windows path traversal
      /etc\/passwd/i
    ],

    # Command injection
    command_injection: [
      /;\s*(ls|cat|rm|wget|curl|bash|sh|nc)\b/i,
      /\|\s*(ls|cat|rm|wget|curl|bash|sh)\b/i,
      /`[^`]*`/,
      /\$\([^)]+\)/
    ],

    # Bot/scanner signatures
    scanner_signatures: [
      /sqlmap/i,
      /nikto/i,
      /nmap/i,
      /masscan/i,
      /burp/i,
      /zap/i,
      /acunetix/i,
      /nessus/i,
      /w3af/i,
      /qualys/i
    ]
  }.freeze

  # User agents that indicate automated scanning
  SUSPICIOUS_USER_AGENTS = [
    /^$/,  # Empty user agent
    /^-$/,
    /curl/i,
    /wget/i,
    /python-requests/i,
    /libwww-perl/i,
    /java/i,
    /scrapy/i,
    /mechanize/i
  ].freeze

  # Paths that should never receive POST/PUT/DELETE from unknown sources
  SENSITIVE_PATHS = %w[
    /api/v1/admin
    /api/v1/auth/login
    /api/v1/auth/register
    /oauth/token
  ].freeze

  # Threshold configuration
  THRESHOLDS = {
    suspicious_request_limit: 10,      # Max suspicious requests per hour
    block_duration_seconds: 3600,       # Block for 1 hour
    progressive_multiplier: 2,          # Double block time for repeat offenders
    max_block_duration: 86_400,         # Max 24 hour block
    rapid_request_threshold: 50,        # Requests per 10 seconds
    payload_size_limit: 10.megabytes    # Max request body size
  }.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    # Skip inspection for trusted paths
    return @app.call(env) if trusted_path?(request.path)

    # Check if IP is currently blocked
    if blocked?(request.ip)
      return blocked_response(request)
    end

    # Run inspection checks
    inspection_result = inspect_request(request)

    if inspection_result[:suspicious]
      handle_suspicious_request(request, inspection_result)
    end

    # Track request for rate analysis
    track_request(request)

    # Call the application
    @app.call(env)
  rescue StandardError => e
    Rails.logger.error("[RequestInspector] Error: #{e.message}")
    @app.call(env)
  end

  private

  # =========================================================================
  # INSPECTION METHODS
  # =========================================================================

  def inspect_request(request)
    result = {
      suspicious: false,
      threats: [],
      score: 0
    }

    # Check for suspicious patterns in request
    check_query_string(request, result)
    check_request_body(request, result)
    check_user_agent(request, result)
    check_headers(request, result)
    check_request_rate(request, result)
    check_payload_size(request, result)

    # Determine if request is suspicious based on score
    result[:suspicious] = result[:score] >= 5
    result
  end

  def check_query_string(request, result)
    query = request.query_string.to_s
    return if query.empty?

    SUSPICIOUS_PATTERNS.each do |threat_type, patterns|
      patterns.each do |pattern|
        if query.match?(pattern)
          result[:threats] << { type: threat_type, location: 'query_string', pattern: pattern.to_s }
          result[:score] += threat_score(threat_type)
        end
      end
    end
  end

  def check_request_body(request, result)
    return unless %w[POST PUT PATCH].include?(request.request_method)

    body = request.body.read
    request.body.rewind
    return if body.empty?

    # Check for malicious patterns in body
    SUSPICIOUS_PATTERNS.each do |threat_type, patterns|
      patterns.each do |pattern|
        if body.match?(pattern)
          result[:threats] << { type: threat_type, location: 'body', pattern: pattern.to_s }
          result[:score] += threat_score(threat_type)
        end
      end
    end
  end

  def check_user_agent(request, result)
    user_agent = request.user_agent.to_s

    SUSPICIOUS_USER_AGENTS.each do |pattern|
      if user_agent.match?(pattern)
        result[:threats] << { type: :suspicious_user_agent, location: 'header', value: user_agent.truncate(100) }
        result[:score] += 2
        break
      end
    end

    # Check for scanner signatures
    SUSPICIOUS_PATTERNS[:scanner_signatures].each do |pattern|
      if user_agent.match?(pattern)
        result[:threats] << { type: :scanner_detected, location: 'user_agent', pattern: pattern.to_s }
        result[:score] += 10  # High score for known scanners
      end
    end
  end

  def check_headers(request, result)
    # Check for missing required headers (potential automated attack)
    if request.get_header('HTTP_ACCEPT').nil? && !api_request?(request)
      result[:threats] << { type: :missing_accept_header, location: 'header' }
      result[:score] += 1
    end

    # Check for suspicious header values
    suspicious_headers = %w[HTTP_X_FORWARDED_FOR HTTP_X_REAL_IP HTTP_VIA HTTP_X_CLUSTER_CLIENT_IP]
    suspicious_headers.each do |header|
      value = request.get_header(header).to_s
      if value.count(',') > 5  # Too many proxies
        result[:threats] << { type: :excessive_proxy_chain, location: 'header', header: header }
        result[:score] += 3
      end
    end
  end

  def check_request_rate(request, result)
    rapid_request_count = get_rapid_request_count(request.ip)

    if rapid_request_count > THRESHOLDS[:rapid_request_threshold]
      result[:threats] << { type: :rapid_requests, count: rapid_request_count }
      result[:score] += 5
    end
  end

  def check_payload_size(request, result)
    content_length = request.content_length.to_i

    if content_length > THRESHOLDS[:payload_size_limit]
      result[:threats] << { type: :oversized_payload, size: content_length }
      result[:score] += 5
    end
  end

  # =========================================================================
  # THREAT SCORING
  # =========================================================================

  def threat_score(threat_type)
    case threat_type
    when :sql_injection then 10
    when :xss then 8
    when :command_injection then 10
    when :path_traversal then 7
    when :scanner_signatures then 10
    else 3
    end
  end

  # =========================================================================
  # BLOCKING LOGIC
  # =========================================================================

  def blocked?(ip)
    Rails.cache.read(block_cache_key(ip)).present?
  end

  def block_ip(ip, duration_seconds: nil)
    # Calculate block duration with progressive penalty
    offense_count = get_offense_count(ip)
    increment_offense_count(ip)

    duration = duration_seconds || calculate_block_duration(offense_count)

    Rails.cache.write(block_cache_key(ip), true, expires_in: duration.seconds)

    log_block(ip, duration, offense_count)
  end

  def calculate_block_duration(offense_count)
    base_duration = THRESHOLDS[:block_duration_seconds]
    multiplier = THRESHOLDS[:progressive_multiplier]**offense_count
    duration = base_duration * multiplier

    [duration, THRESHOLDS[:max_block_duration]].min
  end

  def block_cache_key(ip)
    "ddos_block:#{ip}"
  end

  def get_offense_count(ip)
    Rails.cache.read("ddos_offenses:#{ip}").to_i
  end

  def increment_offense_count(ip)
    current = get_offense_count(ip)
    Rails.cache.write("ddos_offenses:#{ip}", current + 1, expires_in: 7.days)
  end

  # =========================================================================
  # REQUEST TRACKING
  # =========================================================================

  def track_request(request)
    cache_key = "ddos_rapid:#{request.ip}"
    current = Rails.cache.read(cache_key).to_i
    Rails.cache.write(cache_key, current + 1, expires_in: 10.seconds)
  end

  def get_rapid_request_count(ip)
    Rails.cache.read("ddos_rapid:#{ip}").to_i
  end

  def track_suspicious_request(request, result)
    cache_key = "ddos_suspicious:#{request.ip}"
    current = Rails.cache.read(cache_key).to_i
    Rails.cache.write(cache_key, current + 1, expires_in: 1.hour)
    current + 1
  end

  def get_suspicious_count(ip)
    Rails.cache.read("ddos_suspicious:#{ip}").to_i
  end

  # =========================================================================
  # REQUEST HANDLING
  # =========================================================================

  def handle_suspicious_request(request, result)
    suspicious_count = track_suspicious_request(request, result)

    # Log the suspicious activity
    log_suspicious_request(request, result, suspicious_count)

    # Block if threshold exceeded
    if suspicious_count >= THRESHOLDS[:suspicious_request_limit]
      block_ip(request.ip)
    end
  end

  # =========================================================================
  # HELPERS
  # =========================================================================

  def trusted_path?(path)
    # Health checks and public endpoints
    path.match?(%r{^/(health|ready|live|up|favicon|assets)})
  end

  def api_request?(request)
    request.path.start_with?('/api/')
  end

  # =========================================================================
  # RESPONSES
  # =========================================================================

  def blocked_response(request)
    log_blocked_request(request)

    body = {
      success: false,
      error: 'Forbidden',
      message: 'Your IP has been temporarily blocked due to suspicious activity.'
    }.to_json

    [
      403,
      {
        'Content-Type' => 'application/json',
        'X-Request-Blocked' => 'true',
        'Retry-After' => remaining_block_time(request.ip).to_s
      },
      [body]
    ]
  end

  def remaining_block_time(ip)
    # Estimate remaining time (default to 1 hour if unknown)
    ttl = Rails.cache.redis&.ttl(block_cache_key(ip)) || 3600
    [ttl, 0].max
  end

  # =========================================================================
  # LOGGING
  # =========================================================================

  def log_suspicious_request(request, result, count)
    Rails.logger.warn(
      "[DDoS] Suspicious request detected: " \
      "IP=#{request.ip} " \
      "Path=#{request.path} " \
      "Score=#{result[:score]} " \
      "Threats=#{result[:threats].map { |t| t[:type] }.join(', ')} " \
      "Count=#{count}/#{THRESHOLDS[:suspicious_request_limit]}"
    )
  end

  def log_block(ip, duration, offense_count)
    Rails.logger.warn(
      "[DDoS] IP blocked: " \
      "IP=#{ip} " \
      "Duration=#{duration}s " \
      "OffenseCount=#{offense_count}"
    )
  end

  def log_blocked_request(request)
    Rails.logger.warn(
      "[DDoS] Blocked request: " \
      "IP=#{request.ip} " \
      "Path=#{request.path} " \
      "Method=#{request.request_method}"
    )
  end
end
