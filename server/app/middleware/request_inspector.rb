# frozen_string_literal: true

require "cgi"

# Request Inspector Middleware for DDoS Protection
# Analyzes incoming requests for suspicious patterns and potential attacks

class RequestInspector
  # =========================================================================
  # CONFIGURATION
  # =========================================================================

  # Natural-language filler words that follow FROM/INTO/SET in ordinary
  # prose ("select a region FROM THE list", "insert a record INTO THE
  # queue", "set YOUR preferences") but essentially never precede a table,
  # column or value name in actual SQL syntax ("FROM users",
  # "SET password = ?"). Used below to keep the two-keyword co-occurrence
  # rules from firing on free-text search/filter param values.
  SQL_NATURAL_LANGUAGE_FOLLOWERS = /(?:the|a|an|your|my|our|this|these|those|some|any)\b/i

  # Suspicious patterns that indicate potential attacks
  SUSPICIOUS_PATTERNS = {
    # SQL Injection patterns
    #
    # 2026-09-27 (hotfix, operator IP-blocked twice on ops-hub): the
    # SELECT...FROM / DELETE...FROM / INSERT...INTO / UPDATE...SET rules
    # used an unbounded `.*` between the two keywords, which matches an
    # entire ordinary sentence in a free-text search/filter param just as
    # readily as real SQL ("please select a region from the list below"
    # scored as sql_injection). UNION...SELECT and DROP...TABLE are left
    # unbounded — neither co-occurs in ordinary prose — and the negative
    # lookahead only excludes the specific "keyword followed by a filler
    # word" shape prose uses, so "SELECT password FROM users",
    # "DELETE FROM users", "INSERT INTO users" and "UPDATE users SET x"
    # (no filler word after FROM/INTO/SET) are unaffected.
    sql_injection: [
      /(\bUNION\b.*\bSELECT\b|\bSELECT\b.*\bFROM\b(?!\s+#{SQL_NATURAL_LANGUAGE_FOLLOWERS}))/i,
      /(\bDROP\b.*\bTABLE\b|\bDELETE\b.*\bFROM\b(?!\s+#{SQL_NATURAL_LANGUAGE_FOLLOWERS}))/i,
      /(\bINSERT\b.*\bINTO\b(?!\s+#{SQL_NATURAL_LANGUAGE_FOLLOWERS})|\bUPDATE\b.*\bSET\b(?!\s+#{SQL_NATURAL_LANGUAGE_FOLLOWERS}))/i,
      /(\b1\s*=\s*1\b|\b1\s*=\s*'1'\b)/i,
      /(\bOR\b\s+\d+\s*=\s*\d+|\bAND\b\s+\d+\s*=\s*\d+)/i
    ],

    # XSS patterns
    #
    # 2026-09-27 (hotfix): the event-handler rule used to be
    # /on\w+\s*=/i, matched against the raw query string with no markup
    # context at all — it fired on ANY "on<word>=" param, which includes
    # ordinary param names built by tacking a suffix onto "on" purely by
    # coincidence of English (environment=, version_id=, action_category=,
    # include_decisions=, region_id=, notification_type= all contain
    # "on...=" somewhere and all scored 8, crossing the suspicious
    # threshold on completely normal UI traffic and IP-blocking the
    # operator). Real event-handler XSS only means anything inside an HTML
    # tag, so the rule now requires that shape: an unclosed "<" followed by
    # some non-">" tag content, then "on<letters>=".
    xss: [
      /<script\b[^>]*>/i,
      /javascript:/i,
      /<[^>]*\bon[a-z]+\s*=/i,
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
    rapid_request_threshold: 200,       # Requests per RAPID_WINDOW_SECONDS (default; see .rapid_request_threshold)
    payload_size_limit: 10.megabytes    # Max request body size
  }.freeze

  # The window the suspicious-request counter accumulates over — the
  # denominator of suspicious_request_limit.
  SUSPICIOUS_WINDOW_SECONDS = 3600

  # The rapid-request window. Both the per-IP request counter and the
  # "already flagged this window" marker live for exactly this long.
  RAPID_WINDOW_SECONDS = 10

  # AdminSetting key for a THRESHOLDS entry. Rack::Attack, the sibling control
  # in the same request path, has read its limits from AdminSetting since it
  # was written (Rack::Attack.get_rate_limit) — these were a frozen constant,
  # so tuning the two halves of the same defence meant a settings change on one
  # side and a REDEPLOY on the other. Same shape as get_rate_limit: DB value if
  # present and parseable, the constant otherwise, and never an exception (this
  # runs in middleware, ahead of routing).
  def self.setting_key(name) = "ddos_#{name}"

  # Effective value of a THRESHOLDS entry: AdminSetting override, else the
  # compiled-in default. A non-positive or unparseable override is IGNORED
  # rather than honoured — a typo in a settings row must not disable a
  # security control or set a zero-second block.
  def self.threshold(name)
    fallback = THRESHOLDS.fetch(name)
    raw = AdminSetting.find_by(key: setting_key(name))&.value
    return fallback if raw.blank?

    value = Integer(raw.to_s.strip, 10)
    value.positive? ? value : fallback
  rescue StandardError
    THRESHOLDS.fetch(name)
  end

  # Requests per window above which traffic is scored as a flood. The default
  # is deliberately above a browser page load: the platform's own SPA issues
  # 50-100 XHRs in the first seconds of a dashboard (IMP-4f9ee46c0f50 — the
  # old default of 50 IP-blocked an operator for opening the autonomy page).
  #
  # PRECEDENCE: DDOS_RAPID_REQUEST_THRESHOLD, then the AdminSetting, then the
  # constant. The env var stays on top because it is the escape hatch that
  # works when the DATABASE is the thing being flooded — a threshold that can
  # only be raised through a DB read is unreachable in exactly that incident.
  # An unparseable value at either level falls through rather than disabling
  # the check.
  def self.rapid_request_threshold
    raw = ENV["DDOS_RAPID_REQUEST_THRESHOLD"]
    return threshold(:rapid_request_threshold) if raw.blank?

    value = Integer(raw, 10)
    value.positive? ? value : threshold(:rapid_request_threshold)
  rescue ArgumentError, TypeError
    threshold(:rapid_request_threshold)
  end

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
    check_request_body(request, result) unless body_inspection_exempt?(request)
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

    decoded_query = decode_query_string(query)

    SUSPICIOUS_PATTERNS.each do |threat_type, patterns|
      patterns.each do |pattern|
        if decoded_query.match?(pattern)
          result[:threats] << { type: threat_type, location: "query_string", pattern: pattern.to_s }
          result[:score] += threat_score(threat_type)
        end
      end
    end
  end

  # 2026-09-27 (hotfix): patterns used to run against the RAW (still
  # percent-encoded) query string, which meant an encoded attack payload
  # (e.g. "%3Cscript%3E", or an onerror handler with its "=" written
  # "%3D") could slip past every literal-substring rule above. Decoding
  # once, up front, lets the existing plain-text patterns catch the
  # decoded form directly instead of needing an encoded twin of every
  # rule. A query string that fails to decode (malformed percent-encoding)
  # falls back to the raw string rather than raising — this runs in
  # middleware ahead of routing, so an exception here must not take down
  # the request.
  def decode_query_string(query)
    CGI.unescape(query)
  rescue StandardError
    query
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
          result[:threats] << { type: threat_type, location: "body", pattern: pattern.to_s }
          result[:score] += threat_score(threat_type)
        end
      end
    end
  end

  def check_user_agent(request, result)
    user_agent = request.user_agent.to_s

    SUSPICIOUS_USER_AGENTS.each do |pattern|
      if user_agent.match?(pattern)
        result[:threats] << { type: :suspicious_user_agent, location: "header", value: user_agent.truncate(100) }
        result[:score] += 2
        break
      end
    end

    # Check for scanner signatures
    SUSPICIOUS_PATTERNS[:scanner_signatures].each do |pattern|
      if user_agent.match?(pattern)
        result[:threats] << { type: :scanner_detected, location: "user_agent", pattern: pattern.to_s }
        result[:score] += 10  # High score for known scanners
      end
    end
  end

  def check_headers(request, result)
    # Check for missing required headers (potential automated attack)
    if request.get_header("HTTP_ACCEPT").nil? && !api_request?(request)
      result[:threats] << { type: :missing_accept_header, location: "header" }
      result[:score] += 1
    end

    # Check for suspicious header values
    suspicious_headers = %w[HTTP_X_FORWARDED_FOR HTTP_X_REAL_IP HTTP_VIA HTTP_X_CLUSTER_CLIENT_IP]
    suspicious_headers.each do |header|
      value = request.get_header(header).to_s
      if value.count(",") > 5  # Too many proxies
        result[:threats] << { type: :excessive_proxy_chain, location: "header", header: header }
        result[:score] += 3
      end
    end
  end

  # A flood is a per-WINDOW signal, so it is scored at most once per window
  # per IP. Scoring every request past the threshold made one burst equal
  # suspicious_request_limit hits inside a second, i.e. a single page load was
  # a block. A sustained flood still accrues one hit per window and blocks
  # after suspicious_request_limit windows (~100s at the defaults).
  def check_request_rate(request, result)
    rapid_request_count = get_rapid_request_count(request.ip)
    return unless rapid_request_count > self.class.rapid_request_threshold
    return unless flag_rapid_window!(request.ip)

    result[:threats] << { type: :rapid_requests, count: rapid_request_count }
    result[:score] += 5
  end

  # Marks the current window as flagged for the IP. Returns true only the
  # first time in a window; the marker expires with the window. Atomic
  # (SET NX EX) — the read-then-write version let two threads in one burst
  # each score a hit.
  def flag_rapid_window!(ip)
    ::Security::IpBlockStore.claim_rapid_window!(ip, ttl_seconds: RAPID_WINDOW_SECONDS)
  end

  def check_payload_size(request, result)
    content_length = request.content_length.to_i

    if content_length > self.class.threshold(:payload_size_limit)
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
    ::Security::IpBlockStore.blocked?(ip)
  end

  def block_ip(ip, duration_seconds: nil)
    # Calculate block duration with progressive penalty
    offense_count = get_offense_count(ip)
    increment_offense_count(ip)

    duration = duration_seconds || calculate_block_duration(offense_count)

    ::Security::IpBlockStore.block!(ip, duration_seconds: duration)

    log_block(ip, duration, offense_count)
  end

  def calculate_block_duration(offense_count)
    base_duration = self.class.threshold(:block_duration_seconds)
    multiplier = self.class.threshold(:progressive_multiplier)**offense_count
    duration = base_duration * multiplier

    [ duration, self.class.threshold(:max_block_duration) ].min
  end

  def get_offense_count(ip)
    ::Security::IpBlockStore.offense_count(ip)
  end

  def increment_offense_count(ip)
    ::Security::IpBlockStore.bump_offense(ip)
  end

  # =========================================================================
  # REQUEST TRACKING
  # =========================================================================

  def track_request(request)
    ::Security::IpBlockStore.bump_rapid(request.ip, ttl_seconds: RAPID_WINDOW_SECONDS)
  end

  def get_rapid_request_count(ip)
    ::Security::IpBlockStore.rapid_count(ip)
  end

  def track_suspicious_request(request, _result)
    ::Security::IpBlockStore.bump_suspicious(request.ip, ttl_seconds: SUSPICIOUS_WINDOW_SECONDS)
  end

  def get_suspicious_count(ip)
    ::Security::IpBlockStore.suspicious_count(ip)
  end

  # =========================================================================
  # REQUEST HANDLING
  # =========================================================================

  def handle_suspicious_request(request, result)
    suspicious_count = track_suspicious_request(request, result)

    # Log the suspicious activity
    log_suspicious_request(request, result, suspicious_count)

    # Block if threshold exceeded
    if suspicious_count >= self.class.threshold(:suspicious_request_limit)
      block_ip(request.ip)
    end
  end

  # =========================================================================
  # HELPERS
  # =========================================================================

  def trusted_path?(path)
    # Health checks and public endpoints
    return true if path.match?(%r{^/(health|ready|live|up|favicon|assets)})

    # On-node agent + worker + federation traffic. These paths are gated by
    # mTLS or an instance JWT (controller-level auth), so every request is
    # already bound to a specific NodeInstance identity — the anonymous
    # intrusion-heuristics here don't apply. More importantly, inspecting
    # them lets a node's own agent BRICK itself: a transient failure (e.g.
    # a compose that can't fetch its modules) makes the agent retry every
    # endpoint in a tight loop, which trips check_request_rate (>50 req/10s),
    # scores the traffic "suspicious", and IP-blocks the node — after which
    # EVERY node_api call (heartbeat, modules, task lease) 403s and the node
    # can never reach the platform to recover. Rack::Attack safelists these
    # same prefixes for the same reason (see safelist "powernode_node_api").
    # The anonymous device-claim endpoint has no credential at this lifecycle
    # stage, so it stays inspected (matching that safelist's /claim carve-out).
    return false if path == "/api/v1/system/node_api/claim"

    # /api/v1/internal/ is the WORKER→backend channel (embeddings, credential
    # decrypt, LLM proxy), reached over mTLS via localhost:443 and gated by
    # authenticate_worker_via_mtls! — same identity-bound rationale as the
    # node_api prefixes above, and the same self-brick hazard. Omitting it bit
    # on ops-hub 2026-08-02: a codebase index run made ~25k internal calls,
    # tripped check_request_rate, and the platform IP-blocked 127.0.0.1 — its
    # own worker. Every embedding then failed with "Service access forbidden"
    # while the provider credential, egress and OpenAI key were all fine, and
    # nothing appeared in the controller log because this middleware rejects
    # ahead of the controller. A bulk internal operation must not be able to
    # lock the platform out of itself.
    path.start_with?("/api/v1/system/node_api/") ||
      path.start_with?("/api/v1/system/worker_api/") ||
      path.start_with?("/api/v1/system/federation_api/") ||
      path.start_with?("/api/v1/internal/")
  end

  # The MCP streamable-HTTP endpoint (external MCP clients, e.g. Claude Code).
  # OAuth-gated at the controller; its tool payloads legitimately carry CODE —
  # improvement offers, learnings, knowledge entries — which the anonymous body
  # patterns structurally misread as attacks: backtick-quoted spans score as
  # command injection (+10 each) and the boundary-less /on\w+\s*=/ XSS pattern
  # matches ordinary Ruby ("…tion_report ="). On 2026-08-07 a batch of
  # create_improvement calls crossed suspicious_request_limit this way and the
  # platform IP-blocked its own improvement pipeline for an hour — the same
  # self-brick class as the node_api and /api/v1/internal/ incidents above.
  # This middleware runs ahead of routing, so request.path is RAW PATH_INFO —
  # the trailing-slash and .format variants Rails later collapses onto the same
  # controller action are still literally present here, and an exact-string
  # match would miss them (an ordinary client footgun — trailing-slash base
  # URL, appended .json — would reproduce the incident). This pattern covers
  # those two variant shapes; doubled-slash forms (/api/v1/mcp//message) also
  # route but are deliberately NOT matched — that direction fails SAFE (body
  # heuristics still run), and tolerating them would loosen the anchor for a
  # much rarer join-bug shape.
  MCP_MESSAGE_PATH_PATTERN = %r{\A/api/v1/mcp/message/?(\.\w+)?\z}

  # Deliberately NARROWER than trusted_path?: only the request-BODY content
  # heuristics are skipped, and only on the MCP message endpoint. Query-string,
  # user-agent, rate, and payload-size checks still run, and an IP that is
  # already blocked still gets 403 here — this endpoint is reachable from
  # outside, so it must keep its DDoS posture. Note the exemption is purely
  # path-based: the middleware does not verify the OAuth token (that stays the
  # controller's job, which 401s before parsing any body), so an anonymous
  # attack-shaped body POSTed here skips BODY scoring only — it still accrues
  # rate score and still hits an existing block.
  def body_inspection_exempt?(request)
    request.path.match?(MCP_MESSAGE_PATH_PATTERN)
  end

  def api_request?(request)
    request.path.start_with?("/api/")
  end

  # =========================================================================
  # RESPONSES
  # =========================================================================

  def blocked_response(request)
    log_blocked_request(request)

    body = {
      success: false,
      error: "Forbidden",
      message: "Your IP has been temporarily blocked due to suspicious activity."
    }.to_json

    [
      403,
      {
        "Content-Type" => "application/json",
        "X-Request-Blocked" => "true",
        "Retry-After" => remaining_block_time(request.ip).to_s
      },
      [ body ]
    ]
  end

  # Real remaining seconds. This read used to go through Powernode::CacheRedis,
  # which resolves Redis OFF Rails.cache and therefore returned nil for every
  # non-Redis cache store — so on the hub (CACHE_STORE=memory_store) every
  # Retry-After was the 3600 fallback regardless of the actual block.
  def remaining_block_time(ip)
    ::Security::IpBlockStore.block_ttl(ip) || self.class.threshold(:block_duration_seconds)
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
      "Count=#{count}/#{self.class.threshold(:suspicious_request_limit)}"
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
