# frozen_string_literal: true

require "cgi"

# Request Inspector Middleware for DDoS Protection
# Analyzes incoming requests for suspicious patterns and potential attacks

class RequestInspector
  # =========================================================================
  # CONFIGURATION
  # =========================================================================

  # SQL building blocks for the sql_injection rules below. All of it is plain
  # alternation and bounded-by-structure repetition: NO lookaround, backreference
  # or atomic group, so every rule stays eligible for Ruby 3.2's linear-time
  # matcher (a spec asserts Regexp.linear_time? for every rule and a 1 MB
  # adversarial bound). Do not add any of those constructs here: an earlier
  # negative-lookahead fix disabled linear-time matching and 100KB of "select "
  # took 43s on a pre-auth path that reads bodies up to 10MB.
  #
  # SQL_SEP is one separator: whitespace, a '+' (a space in a raw query string)
  # or an inline /* comment */ (the classic way to keep keywords apart; the body
  # tolerates '*' characters so /***/ and /*a*b*/ are separators too).
  SQL_SEP = %q{(?:[\s+]|/\*(?:[^*]|\*+[^*/])*\*+/)}
  SQL_NAME = %q{(?:[\w$@#]+|`[^`]*`|"[^"]*"|\[[^\]]*\])}
  # A possibly schema-qualified name, each part bare or `quoted`, "quoted" or
  # [bracketed]; '..' (MSSQL db..table) is tolerated.
  SQL_IDENT = %Q{#{SQL_NAME}(?:\\.+#{SQL_NAME})*}
  # A parenthesised argument list, one level of nesting deep.
  SQL_ARGS = %q{\((?:[^()]|\([^()]*\))*\)}
  # One select-list term: *, a name or function call, or a quoted literal.
  SQL_TERM = %Q{(?:\\*|#{SQL_IDENT}(?:#{SQL_ARGS})?|'[^']*')}
  # A select-list item: a term, optionally concatenated with '||', optionally
  # given an explicit AS alias.
  SQL_ITEM = %Q{#{SQL_TERM}(?:#{SQL_SEP}*\\|\\|#{SQL_SEP}*#{SQL_TERM})*(?:#{SQL_SEP}+AS#{SQL_SEP}+#{SQL_IDENT})?}
  # MSSQL's TOP n may precede the list.
  SQL_TOP = %Q{(?:TOP#{SQL_SEP}*\\(?\\d+\\)?#{SQL_SEP}+)?}
  # Modifiers that may precede the list.
  SQL_SELECT_MODIFIER = %Q{(?:(?:ALL|DISTINCT|HIGH_PRIORITY|STRAIGHT_JOIN|SQL_CALC_FOUND_ROWS|SQL_NO_CACHE|SQL_SMALL_RESULT)#{SQL_SEP}+)*}
  # A select list that is SQL-shaped on its own: a bare star, or a call whose
  # arguments are not a word ("count(*)", "version()", "sleep(5)", "f('x')"). No
  # English sentence needs the table slot checked after one of these; "file(s)"
  # and "item(s)" are prose and take the bare-list path below.
  SQL_STRONG_LIST = %Q{(?:\\*|#{SQL_IDENT}\\((?:#{SQL_SEP}*|\\*|\\d+|[^()]*['"][^()]*)\\))}
  # Everything else (one or several words, a comma list) is also what an English
  # sentence looks like, so that shape must be confirmed by what follows the
  # table.
  SQL_BARE_LIST = %Q{#{SQL_ITEM}(?:#{SQL_SEP}*,#{SQL_SEP}*#{SQL_ITEM})*}
  # A table slot, optionally parenthesised, optionally given an explicit AS alias.
  SQL_TABLE = %Q{\\(?#{SQL_IDENT}\\)?(?:#{SQL_SEP}+AS#{SQL_SEP}+#{SQL_IDENT})?}
  # The clause keywords that may follow a table.
  SQL_CLAUSE = "(?:WHERE|LIMIT|ORDER|GROUP|HAVING|JOIN|INNER|LEFT|RIGHT|NATURAL|CROSS|FULL|OUTER|UNION|EXCEPT|INTERSECT|" \
               "USING|RETURNING|OFFSET|FETCH|FOR|INTO|PROCEDURE|WINDOW)"
  # A statement terminator, closing paren, comment marker or closing double
  # quote (the end of a JSON string value). A single quote is NOT one:
  # "Bob's account" must not read as a closed string.
  SQL_TERMINATOR = %q{(?:[;)]|--|#|/\*)}
  # ...which, directly after the table, may also be that closing quote. After a
  # one-word ALIAS it may not: {"q":"select one from the list"} is prose with a
  # table-and-alias lookalike, and only the strict set confirms an alias.
  SQL_TERMINATOR_OR_QUOTE = %q{(?:[;)"]|--|#|/\*)}
  # What may follow the table slot of a bare-list SELECT or a DELETE: a
  # terminator, a clause keyword, a one-word alias followed by either of those,
  # or the end of the input. Prose puts another ordinary word there ("...from
  # the list"), which is the whole difference between the two once the keywords
  # are present.
  SQL_AFTER_TABLE = "(?:#{SQL_SEP}*#{SQL_TERMINATOR_OR_QUOTE}|#{SQL_SEP}*\\z|#{SQL_SEP}+#{SQL_CLAUSE}\\b|" \
                    "#{SQL_SEP}+#{SQL_IDENT}(?:#{SQL_SEP}*#{SQL_TERMINATOR}|#{SQL_SEP}+#{SQL_CLAUSE}\\b))"
  # Same, for a SELECT whose table may also be followed by '&' (the next query
  # string parameter): the documented prose residue below applies to it.
  SQL_AFTER_TABLE_QS = "(?:#{SQL_AFTER_TABLE}|#{SQL_SEP}*&)"
  # What a subquery's SELECT must be followed by to count: a star, a paren, a
  # digit or quote, or a name that continues as a list, call or FROM.
  SQL_SUBQUERY_BODY = %Q{(?:#{SQL_SEP}*[(*'\\d]|#{SQL_SEP}+#{SQL_IDENT}(?:#{SQL_SEP}*[,(]|#{SQL_SEP}+FROM\\b))}

  # The rules that require SQL structure (see the sql_injection comment below).
  # These are the ones scanned in bounded windows by #match_rule?.
  STRUCTURAL_SQL_RULES = [
    /\bSELECT#{SQL_SEP}+#{SQL_SELECT_MODIFIER}#{SQL_TOP}#{SQL_STRONG_LIST}#{SQL_SEP}+FROM#{SQL_SEP}*#{SQL_TABLE}/i,
    /\bSELECT#{SQL_SEP}+#{SQL_SELECT_MODIFIER}#{SQL_TOP}#{SQL_BARE_LIST}#{SQL_SEP}+FROM#{SQL_SEP}*#{SQL_TABLE}#{SQL_AFTER_TABLE_QS}/i,
    # A parenthesised list straight into a parenthesised table: SELECT(name)FROM(users).
    /\bSELECT#{SQL_SEP}*#{SQL_ARGS}#{SQL_SEP}*FROM#{SQL_SEP}*\(/i,
    # A subquery in the FROM slot, the shape of sqlmap's time- and error-based
    # payloads: "(SELECT 1 FROM (SELECT(SLEEP(5)))a)". Prose has no "from (select".
    /\bFROM#{SQL_SEP}*\(#{SQL_SEP}*SELECT#{SQL_SUBQUERY_BODY}/i,
    /\bDELETE#{SQL_SEP}+(?:(?:LOW_PRIORITY|QUICK|IGNORE)#{SQL_SEP}+)*FROM#{SQL_SEP}+#{SQL_TABLE}#{SQL_AFTER_TABLE}/i,
    /\bINSERT#{SQL_SEP}+(?:(?:LOW_PRIORITY|DELAYED|HIGH_PRIORITY|IGNORE)#{SQL_SEP}+)*INTO#{SQL_SEP}+#{SQL_TABLE}#{SQL_SEP}*(?:#{SQL_ARGS}#{SQL_SEP}*(?:VALUES?|SELECT)\b|VALUES?#{SQL_SEP}*\(|SELECT#{SQL_SEP}+(?:\*|#{SQL_ITEM})#{SQL_SEP}+FROM\b|DEFAULT#{SQL_SEP}+VALUES\b|SET#{SQL_SEP}+#{SQL_IDENT}#{SQL_SEP}*=)/i,
    /\bUPDATE#{SQL_SEP}+(?:(?:LOW_PRIORITY|IGNORE|ONLY)#{SQL_SEP}+)*#{SQL_IDENT}(?:#{SQL_SEP}+(?:AS#{SQL_SEP}+)?#{SQL_NAME})?#{SQL_SEP}+SET#{SQL_SEP}+#{SQL_IDENT}#{SQL_SEP}*=/i
  ].freeze

  # The structural SQL rules are large (1-1.6KB of pattern), and even Ruby's
  # linear-time matcher costs input x pattern size on them (seconds, hundreds of
  # MB, for 10MB of adversarial whitespace). A per-regexp match timeout was tried
  # and REJECTED: every Regexp::TimeoutError leaks the matcher's memoization
  # table (about 200MB at 10MB, never reclaimed), so a handful of large bodies
  # exhaust the process. Instead the structural rules scan a bounded prefix of
  # the text in small windows (see #match_rule?), which caps both CPU and memory
  # per request whatever the input. Accepted residue: a payload that only begins
  # after SQL_SCAN_LIMIT_BYTES of padding is not seen by the structural rules
  # (the unchanged UNION/DROP/tautology rules still scan everything).
  SQL_SCAN_LIMIT_BYTES = 256 * 1024
  SQL_SCAN_WINDOW_BYTES = 64 * 1024
  SQL_SCAN_OVERLAP_BYTES = 2 * 1024

  # Suspicious patterns that indicate potential attacks
  SUSPICIOUS_PATTERNS = {
    # SQL Injection patterns.
    #
    # IMP-a09101cb2a57. SELECT...FROM, DELETE...FROM, INSERT...INTO and
    # UPDATE...SET used to match ANY text between their two keywords, so
    # ordinary English in a free-text param ("select a region from the list",
    # "update your account and set preferences") scored as sql_injection and fed
    # the progressive IP block, the same lockout class as the 2026-09-27 XSS
    # incident. They now require the SQL STRUCTURE around the keywords instead
    # of trying to exclude prose:
    #   SELECT <list> FROM <table> <terminator|clause|end>
    #   DELETE FROM <table> <terminator|clause|end>
    #   INSERT INTO <table> (columns) | VALUES | SELECT | SET
    #   UPDATE <table> SET <column> =
    # A bare "select password from users" is still flagged (it is SQL); an
    # English sentence has another word after the table slot, so it is not.
    #
    # Accepted residue: a prose value that happens to be exactly "select X from
    # Y" with nothing after it IS this shape and still scores; telling it apart
    # from SQL would need excluding prose, which this change deliberately does
    # not do. The UNION...SELECT, DROP...TABLE, tautology and AND/OR rules are
    # unchanged. History: the 2026-09-27 round-1 negative lookahead was REVERTED
    # for ReDoS (it disabled the linear-time matcher).
    sql_injection: [
      /\bUNION\b.*\bSELECT\b/i,
      *STRUCTURAL_SQL_RULES,
      /\bDROP\b.*\bTABLE\b/i,
      /(\b1\s*=\s*1\b|\b1\s*=\s*'1'\b)/i,
      /(\bOR\b\s+\d+\s*=\s*\d+|\bAND\b\s+\d+\s*=\s*\d+)/i
    ],

    # XSS patterns.
    #
    # 2026-09-27 hotfix: the event-handler rule used to be /on\w+\s*=/i,
    # matched against the raw query string with no markup context at all —
    # it fired on ANY "on<word>=" param, which includes ordinary param
    # names built by tacking a suffix onto "on" purely by coincidence of
    # English (environment=, version_id=, action_category=,
    # include_decisions=, region_id=, notification_type= all contain
    # "on...=" somewhere and all scored 8, crossing the suspicious
    # threshold on completely normal UI traffic and IP-blocking the
    # operator).
    #
    # Round 2 (reviewer): the round-1 replacement, /<[^>]*\bon[a-z]+\s*=/i,
    # missed a quoted '>' inside an attribute value (`<img alt=">"
    # onerror=alert(1)>` — the `[^>]*` stops at the FIRST '>', which is
    # the one INSIDE the quoted alt value, so it never reaches "onerror=").
    # This version segments the tag content into quoted spans ("...' or
    # '...') and unquoted spans ([^>"']*), each parsed independently, so a
    # '>' or 'on...=' inside a quoted value can't be mistaken for the tag
    # boundary — the same technique used to keep this kind of scan linear
    # (no ambiguous overlap between the quoted and unquoted alternatives,
    # so no catastrophic backtracking; deliberately has NO lookaround, per
    # the ReDoS finding on the sql_injection lookahead above).
    #
    # Known gap (round 3, reviewer, LOW): a STRAY, unpaired quote before
    # the handler defeats this rule — `<img src=x" onerror=alert(1)>` has
    # one unmatched '"' with no closing partner, so the quoted-span
    # alternative can never close and the unquoted span can't cross it
    # either; nothing after the stray quote can reach "on[a-z]+\s*=".
    # Accepted as a known limitation: closing it invites a broader,
    # quote-balancing scheme, which is exactly the kind of complexity
    # round 2 spent a ReDoS incident closing off. Pinned by a spec, not
    # left undocumented.
    #
    # Deliberate, NOT a gap: a bare "on...=" with no preceding '<' at all
    # (e.g. `x" onfocus=alert(1)`) is NOT flagged. That is the entire
    # point of round 1 — the pre-hotfix rule (/on\w+\s*=/i) matched this
    # shape unconditionally and false-positived on ordinary param names
    # (version_id=, notification_type=, ...). Also pinned by a spec, so a
    # future "fix" doesn't quietly reopen the round-1 incident.
    xss: [
      /<script\b[^>]*>/i,
      /javascript:/i,
      /<[a-z!\/][^>"']*(?:(?:"[^"]*"|'[^']*')[^>"']*)*\bon[a-z]+\s*=/i,
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

  # One rule against one text. The unchanged `.*` rules scan the whole text as
  # before. The STRUCTURAL rules scan a bounded prefix in small overlapping
  # windows (see SQL_SCAN_LIMIT_BYTES): their cost is input x pattern size, and
  # a window keeps the matcher's working memory small and freed, where a single
  # scan over megabytes of adversarial text does not. A window that stops
  # mid-text is cut at whitespace and ended with a control character, so the
  # end-of-input alternative (\z) never fires on a cut.
  def match_rule?(text, pattern)
    return pattern.match?(text) unless STRUCTURAL_SQL_RULES.include?(pattern)

    each_sql_window(text).any? { |window| pattern.match?(window) }
  end

  def each_sql_window(text)
    return [ text ] if text.bytesize <= SQL_SCAN_WINDOW_BYTES

    Enumerator.new do |yielder|
      limit = [ text.bytesize, SQL_SCAN_LIMIT_BYTES ].min
      start = 0
      while start < limit
        stop = [ start + SQL_SCAN_WINDOW_BYTES, limit ].min
        chunk = text.byteslice(start, stop - start).to_s.scrub("")
        last = stop >= limit
        if !last && (cut = chunk.rindex(/\s/))
          chunk = chunk[0, cut]
        end
        yielder << (last && limit == text.bytesize ? chunk : "#{chunk}\u0001")
        break if last

        start += [ chunk.bytesize - SQL_SCAN_OVERLAP_BYTES, SQL_SCAN_WINDOW_BYTES / 2 ].max
      end
    end
  end

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

    # Every threat class EXCEPT xss runs against the raw (still
    # percent-encoded) query string, exactly as before this hotfix.
    #
    # Round 2 (reviewer): round 1 decoded the WHOLE query string once and
    # matched every rule against the decoded form, which introduced its
    # own false positives — an encoded backtick/space/etc turning an
    # ordinary value into a command_injection or sql_injection hit
    # (`q=%60rails%20console%60`, `q=select%20all%20items%20from%20inventory`)
    # — on top of the ReDoS and invalid-UTF-8 issues below. Only the XSS
    # rule actually needs the decoded form (an encoded onerror= attack must
    # still be caught); every other rule stays on the raw string.
    scrubbed_query = safe_string(query)
    SUSPICIOUS_PATTERNS.each do |threat_type, patterns|
      next if threat_type == :xss

      patterns.each do |pattern|
        if match_rule?(scrubbed_query, pattern)
          result[:threats] << { type: threat_type, location: "query_string", pattern: pattern.to_s }
          result[:score] += threat_score(threat_type)
        end
      end
    end

    check_query_string_xss(query, result)
  end

  # 2026-09-27 hotfix. Bugs found across two reviews of the per-parameter
  # decode:
  #
  #   1. HIGH (round 2) — CGI.unescape("%FF") produces a string with an
  #      invalid UTF-8 byte, which #match? then raises ArgumentError on.
  #      That exception escaped inspect_request entirely and was
  #      swallowed by #call's own top-level rescue, which passes the
  #      request through COMPLETELY UNINSPECTED (no body check, no UA
  #      check, no rate tracking) — a single stray %FF anywhere in the
  #      query string was a full bypass.
  #   2. MEDIUM (round 2) — a '<' in one param's value could combine with
  #      an unrelated "on...=" NAME in a LATER param into a false tag
  #      match (`q=a%3Cb&online=true` decoded as one blob reads
  #      "...a<b&online=true...", and the tag-context rule can't tell the
  #      '<' and the "on...=" came from different params).
  #   3. MEDIUM (round 3) — round 2's fix for #2 went one step too far: it
  #      split each param into KEY and VALUE and matched them SEPARATELY,
  #      which let an attack split across the "=" evade entirely — a tag
  #      opening in the key half, the handler in the value half
  #      (`%3Cimg%20src=x%20onerror=alert(1)%3E` decodes to key "<img
  #      src", value "x onerror=alert(1)>" — neither half alone matches).
  #      Matching the WHOLE decoded pair (not key and value separately)
  #      fixes this without reopening #2: splitting on '&' still keeps
  #      different PARAMS' pairs apart, it just no longer ALSO splits
  #      within one param's own pair.
  #   4. LOW (round 3) — splitting on /[&;]/ was wrong twice over: it ran
  #      on the unscrubbed RAW query string, so a raw invalid byte in the
  #      query string itself (not just one CGI.unescape produces) raised
  #      out of String#split before decoding ever started; and Rack 3
  #      does not treat ';' as a query separator at all, so a ';' inside
  #      an attribute value (`q=<img alt=";" onerror=alert(1)>`) was
  #      wrongly treated as a param boundary and fragmented the payload
  #      across two "params" that neither matched alone.
  #
  # Splitting the SCRUBBED string, on '&' only, into whole pairs — each
  # pair decoded and matched as ONE piece — fixes all four: a raw invalid
  # byte can't survive to #split, CGI.unescape's invalid bytes can't
  # survive to #match? (see #safe_string), ';' is no longer a false
  # boundary, and an attack spanning the '=' can't be severed by one.
  def check_query_string_xss(query, result)
    safe_string(query).split("&").each do |pair|
      piece = decode_query_component(pair)
      next if piece.nil? || piece.empty?

      SUSPICIOUS_PATTERNS[:xss].each do |pattern|
        if piece.match?(pattern)
          result[:threats] << { type: :xss, location: "query_string", pattern: pattern.to_s }
          result[:score] += threat_score(:xss)
        end
      end
    end
  end

  # CGI.unescape itself does not raise on malformed percent-encoding (an
  # incomplete "%2" or similar is simply left literal), but the STRING IT
  # PRODUCES can carry an invalid byte sequence for the string's encoding
  # (CGI.unescape("%FF") is exactly this) — #scrub fixes that up before
  # anything ever matches against it. The rescue is defense in depth for
  # any other decode failure; a component that fails to decode is scrubbed
  # and matched in its raw (still-encoded) form rather than skipped.
  def decode_query_component(component)
    return nil if component.nil?

    safe_string(CGI.unescape(component))
  rescue StandardError
    safe_string(component)
  end

  # 2026-09-27 hotfix, round 2 (reviewer): "make sure no pattern-match
  # exception can skip inspection ... at minimum, scrub every string
  # before matching." An invalid byte sequence for the string's encoding
  # makes Regexp#match?/#match? raise ArgumentError — not caught by any
  # per-check rescue, so it propagates out of inspect_request and is
  # swallowed by #call's top-level rescue, which lets the request through
  # WITHOUT running any of the other checks. #scrub replaces invalid bytes
  # with the Unicode replacement character up front, so a pattern can
  # still fail to MATCH an attack hidden behind bad encoding, but it can
  # never raise and skip every remaining check because of it.
  def safe_string(value)
    value.to_s.scrub
  end

  def check_request_body(request, result)
    return unless %w[POST PUT PATCH].include?(request.request_method)

    body = request.body.read
    request.body.rewind
    return if body.empty?

    # #scrub before matching — see #safe_string: an invalid byte sequence
    # in the raw body must not raise out of every remaining check.
    body = safe_string(body)

    # Check for malicious patterns in body. xss is handled separately —
    # see #check_body_xss.
    SUSPICIOUS_PATTERNS.each do |threat_type, patterns|
      next if threat_type == :xss

      patterns.each do |pattern|
        if match_rule?(body, pattern)
          result[:threats] << { type: threat_type, location: "body", pattern: pattern.to_s }
          result[:score] += threat_score(threat_type)
        end
      end
    end

    check_body_xss(body, result)
  end

  # Round 3 (reviewer, MEDIUM — corrected after an in-transit HTML-rendering
  # mistake in the original finding): a JSON string value can carry its
  # angle brackets as a JSON unicode escape — the six literal characters
  # backslash, u, 0, 0, 3, c (and backslash, u, 0, 0, 3, e for the closing
  # bracket) — rather than literal '<'/'>'. This middleware sees the RAW
  # body ahead of any JSON.parse, so those six characters are still
  # sitting there literally; Rails' own JSON parser would turn them back
  # into '<'/'>' before the app ever saw the value, so scanning the raw
  # bytes without accounting for this escapes detection entirely. The
  # pre-hotfix rule matched a bare "on...=" substring with no tag
  # requirement at all, so it still caught this; the round-1/2 tag-context
  # rule needs an actual '<'/'>' to work with. Un-escaping the two
  # sequences (case-insensitively — an uppercase hex digit is equally
  # valid) is a plain literal-substring replacement — linear, no
  # backtracking risk — and is scoped to the XSS check only, same "decode
  # only where it's needed" principle as the query-string split in
  # #check_query_string_xss.
  #
  # Deliberately NOT decoded: HTML entities (&lt;/&gt;). An entity-escaped
  # tag cannot execute as markup — decoding those would only manufacture a
  # false positive (e.g. a user pasting escaped HTML into an ordinary text
  # field). See the "known limits" spec pinning this.
  def check_body_xss(body, result)
    unescaped = body.gsub(/\\u003c/i, "<").gsub(/\\u003e/i, ">")

    SUSPICIOUS_PATTERNS[:xss].each do |pattern|
      if unescaped.match?(pattern)
        result[:threats] << { type: :xss, location: "body", pattern: pattern.to_s }
        result[:score] += threat_score(:xss)
      end
    end
  end

  def check_user_agent(request, result)
    user_agent = safe_string(request.user_agent)

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
  # already blocked still gets 429 here — this endpoint is reachable from
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

  # 429, not 403. A 403 here read as "wrong credentials / no permission" to a
  # blocked operator (POST /api/v1/auth/login 403'd before the sessions
  # controller ran, so the password looked broken). 429 + Retry-After is the
  # standard "back off" signal, and the body carries a stable machine code plus
  # the remaining seconds so clients can say what actually happened. Consumers
  # key on `code` / X-Request-Blocked, never on the message text.
  BLOCKED_CODE = "ip_blocked"

  def blocked_response(request)
    log_blocked_request(request)

    retry_after = remaining_block_time(request.ip)
    body = {
      success: false,
      error: "Too Many Requests",
      code: BLOCKED_CODE,
      message: "Your IP has been temporarily blocked due to suspicious activity.",
      retry_after_seconds: retry_after
    }.to_json

    [
      429,
      {
        "Content-Type" => "application/json",
        "X-Request-Blocked" => "true",
        "Retry-After" => retry_after.to_s
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
