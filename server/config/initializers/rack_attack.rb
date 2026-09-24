# frozen_string_literal: true

class Rack::Attack
  # =========================================================================
  # CONFIGURATION
  # =========================================================================

  # Enable rate limiting in all environments (can be disabled via env var)
  Rails.application.config.rate_limiting_enabled = !Rails.env.test? && ENV["DISABLE_RATE_LIMITING"] != "true"

  # =========================================================================
  # HELPER METHODS
  # =========================================================================

  # Helper method to get rate limits from admin settings
  def self.get_rate_limit(setting_key, fallback_limit)
    AdminSetting.find_by(key: setting_key)&.value&.to_i || fallback_limit
  rescue StandardError
    fallback_limit
  end

  # Helper method to check if rate limiting is enabled at runtime.
  #
  # Delegates to the config assigned above rather than recomputing the
  # predicate, because the two DID drift and the drift was invisible: the
  # config excluded test, this helper did not, and every throttle proc calls
  # THIS one. So the auth throttles ran live during the suite with their real
  # limits (auth_login_by_email 5/hour, password reset 3/hour) against a
  # 1-hour window shared by the whole run.
  #
  # That made the password specs order- and timing-dependent — they 429 or pass
  # depending on where a randomised run happens to place them, which is exactly
  # how it presented: five spec/requests/api/v1/auth/passwords_spec.rb failures
  # on one machine and none on another, from identical code.
  #
  # One definition, one source of truth. A future environment exclusion added
  # to the config is now automatically honoured at runtime.
  def self.rate_limiting_enabled?
    Rails.application.config.rate_limiting_enabled
  end

  # Extract user from JWT token
  #
  # IMP-99e8e4701150 review B1/N1 — TWO bugs, fixed together (fixing either
  # alone leaves the same class of gap open the other way):
  #
  # B1 — header parsing required a literal `"Bearer "` prefix
  # (`start_with?("Bearer ")`), but the app's own auth
  # (Authentication#authenticate_request, app/controllers/concerns/
  # authentication.rb) parses with `header.split(" ").last` — no scheme
  # check at all. A request carrying the bare JWT with no `"Bearer "` prefix
  # authenticates NORMALLY (the app's parser returns the whole string when
  # there's no space to split on) while resolving to NO user here — every
  # throttle/safelist keyed on this method (impersonation_by_user,
  # admin_users, two_factor_reauth_by_user, extract_account_from_request's
  # JWT branch) silently treated a real, authenticated caller as anonymous.
  # That is precisely how the per-user 2FA re-auth throttle was bypassed:
  # omit "Bearer " and the IP throttle is the only one left standing.
  #
  # N1 — `JWT.decode(..., algorithm: "HS256")` hardcoded the algorithm
  # instead of going through Security::JwtService, which already resolves
  # the CONFIGURED algorithm (JWT_ALGORITHM; HS256 is only the default) and
  # replays the exact rotation-grace-key and issuer/audience handling real
  # requests get. Deploy the app with JWT_ALGORITHM=RS256 and this hardcoded
  # HS256 verify fails for every token — silently, back to the SAME
  # no-user-resolved gap as B1, just triggered by config instead of a
  # missing header prefix.
  #
  # QUIET vs LOUD, preserved from before this fix: a token that fails to
  # DECODE (bad signature, expired, blacklisted, malformed — the ordinary
  # shape of anonymous/stale-token traffic) resolves to nil silently. Only a
  # failure AFTER a token decodes successfully (i.e., the `User.find_by`
  # lookup itself raising — a transient DB error, not a bad token) fails
  # open LOUDLY, logged at ERROR, because that is the case nothing else
  # would ever surface. This method is called directly by several throttles
  # below (not only via #extract_account_from_request), so a rescue scoped
  # to one caller would not cover the others.
  # Memoized per REQUEST (env), same pattern as #extract_account_from_request
  # below — and for the identical reason. This is called directly by several
  # throttles/safelists (impersonation_by_user, admin_users,
  # two_factor_reauth_by_user, ...) AND indirectly via
  # #extract_account_from_request, so a single request can reach it up to
  # several times. #resolve_user_from_request now does a real
  # Security::JwtService.decode (blacklist check included — a DB or Redis
  # round trip, not the free in-memory JWT.decode this replaced), so
  # re-running it per call is real, repeated cost, not just repeated work.
  # `env.key?` distinguishes "resolved to nil" (cached) from "not yet
  # resolved", so a request with no/invalid token isn't re-decoded on every
  # subsequent call either.
  def self.extract_user_from_request(request)
    env = request.env
    return env["rack_attack.user"] if env.key?("rack_attack.user")

    env["rack_attack.user"] = resolve_user_from_request(request)
  end

  def self.resolve_user_from_request(request)
    auth_header = request.get_header("HTTP_AUTHORIZATION")
    return nil if auth_header.blank?

    token = auth_header.split(" ").last
    return nil if token.blank?

    begin
      payload = Security::JwtService.decode(token)
    rescue StandardError
      return nil
    end

    # The access token carries the user id in the standard "sub" claim; older
    # tokens used "user_id". Without reading "sub", every authenticated request
    # resolves to no user → no account → the strict anonymous throttles apply.
    user_id = payload[:sub] || payload[:user_id]
    return nil if user_id.blank?

    User.find_by(id: user_id)
  rescue StandardError => e
    Rails.logger.error(
      "[RackAttack] extract_user_from_request failed to look up user — failing open " \
      "(no user/account attribution for this request; anonymous/IP-based limits still apply): " \
      "#{e.class}: #{e.message}"
    )
    nil
  end
  private_class_method :resolve_user_from_request

  # Extract account from request (via user or API key)
  #
  # IMP-24df1ec74489 — TWO bugs here, both fixed together (fixing the
  # column name alone would trade a loud failure for a silent one — see
  # below). `api_keys` has a `key_digest` column, not `key_hash` (schema
  # drift; PG::UndefinedColumn on every request carrying an X-API-Key
  # header, unrescued at most of #extract_account_from_request's call
  # sites — including the "extreme_abuse" blocklist, which runs
  # unconditionally for every request — reproduced end to end via a real
  # request through that path, which 500s). AND the digest scheme was
  # wrong: `Digest::SHA256.hexdigest(api_key)` (bare) never equals what
  # ApiKey#generate_key actually writes to key_digest, which is
  # `ApiKey.hash_key(api_key)` =
  # `Digest::SHA256.hexdigest("#{secret_key_base}:#{api_key}")` — verified
  # by executing the real write path and comparing both candidate digests
  # against the stored value before writing this fix, not assumed.
  # Renaming the column reference alone would have converted today's loud
  # error into a silent never-match: every lookup would miss, attribution
  # would always be nil, and nothing would ever indicate why.
  #
  # Rescued here as ONE `rescue` wrapping the whole resolution (user
  # lookup, its `.account` association load, the API-key lookup, and ITS
  # `.account` load — review follow-up: a narrower rescue around only the
  # API-key query left the user/JWT branch, which most authenticated
  # requests take, exposed to the identical unrescued-helper -> 500 path)
  # rather than at each of the many call sites below: a transient DB error
  # must fail OPEN for this one account-attribution lookup (falls back to
  # anonymous/IP-based throttling for this request) rather than 500 every
  # request — but per the "a rate limiter that silently stops limiting is
  # the dangerous direction" principle, failing open here is logged at
  # ERROR naming why, not swallowed silently the way client_ip's identical
  # rescue above is (that one falls back to an equally-valid IP; this one
  # gives up an entire attribution dimension).
  #
  # Memoized per request (env-scoped — NOT class- or thread-level, which
  # would leak across requests): every account-keyed throttle below calls
  # this at least twice, once in its discriminator and once in its
  # `limit:` proc, and several throttles share it, so a single
  # authenticated `/api/` request would otherwise repeat this same
  # resolution (a JWT decode plus a DB query, or two DB queries) many
  # times over. A plain `||=` would be wrong here: a fail-open lookup
  # legitimately resolves to `nil` (no account), and `||=` would treat that
  # as "not yet cached" and repeat the query every single time — the
  # common case for unauthenticated traffic. `env.key?` distinguishes
  # "resolved to nil" from "not yet resolved."
  def self.extract_account_from_request(request)
    env = request.env
    return env["rack_attack.account"] if env.key?("rack_attack.account")

    env["rack_attack.account"] = resolve_account_from_request(request)
  end

  def self.resolve_account_from_request(request)
    # Try to get from user first
    user = extract_user_from_request(request)
    return user.account if user&.account

    # Try to get from API key
    api_key = request.get_header("HTTP_X_API_KEY")
    if api_key
      key = ApiKey.active.find_by(key_digest: ApiKey.hash_key(api_key))
      return key.account if key&.account
    end

    nil
  rescue StandardError => e
    Rails.logger.error(
      "[RackAttack] extract_account_from_request failed to resolve account — failing open " \
      "(no account attribution for this request; anonymous/IP-based limits still apply): " \
      "#{e.class}: #{e.message}"
    )
    nil
  end
  private_class_method :resolve_account_from_request

  # Real client IP. ActionDispatch::RemoteIp runs before Rack::Attack in the
  # middleware stack and resolves the client from X-Forwarded-For (honoring
  # trusted proxies), so IP-keyed throttles key on the actual client rather than
  # the reverse proxy's shared address. Falls back to the Rack peer IP.
  def self.client_ip(request)
    # .to_s lazily resolves the IP and can raise IpSpoofAttackError on a
    # mismatched forwarded-header chain; fall back to the peer IP rather than
    # letting a throttle discriminator error the request.
    request.env["action_dispatch.remote_ip"]&.to_s.presence || request.ip
  rescue StandardError
    request.ip
  end

  # Get tier-based limit for an account
  def self.tier_based_limit(account, limit_type)
    return 999_999 unless rate_limiting_enabled?

    tier = RateLimiting::TieredService.tier_for_account(account)
    config = RateLimiting::TieredService.tier_config(tier)
    config[limit_type.to_sym] || 999_999
  end

  # IMP-99e8e4701150 review M1. Matches the two 2FA "re-authentication" writes
  # — disabling 2FA and regenerating backup codes — which both accept a
  # TOTP/backup code from an ALREADY-authenticated session. `auth_2fa_by_ip`
  # below only matches POST, so it never saw DELETE /two_factor/disable at
  # all; a wrong-code guess there was unthrottled by IP or by user.
  def self.two_factor_reauth_path?(request)
    (request.path.end_with?("/two_factor/disable") && request.delete?) ||
      (request.path.end_with?("/two_factor/regenerate_backup_codes") && request.post?)
  end

  # =========================================================================
  # THROTTLE RULES
  # =========================================================================

  # Anonymous device-claim polling (POST /api/v1/system/node_api/claim).
  # Unauthenticated at this lifecycle stage, so it must be rate-limited to
  # prevent unbounded UnclaimedDevice row creation from one source. A real
  # device polls every ~30s (2/min); 20/min/IP leaves wide headroom while
  # capping a flood. See audit 2026-06-09 finding F6-03.
  #
  # Registered OUTSIDE the test-env guard below so the rule itself is
  # testable (extensions/system claim_throttle_spec.rb). The test-env
  # fallback is effectively unlimited so unrelated request specs hitting
  # the claim endpoint never trip it — the throttle spec opts in by
  # stubbing get_rate_limit.
  throttle("system_node_claim_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("node_claim_attempts_per_minute", Rails.env.test? ? 999_999 : 20) : 999_999 }, period: 1.minute) do |request|
    client_ip(request) if request.path == "/api/v1/system/node_api/claim" && request.post?
  end

  # 2FA re-auth (disable / regenerate_backup_codes) — IMP-99e8e4701150 review
  # M1. Tight and short-windowed: these actions gate turning 2FA off and
  # invalidating every existing backup code, so a caller grinding TOTP/backup
  # codes against them is exactly what this must stop. TWO throttles, IP and
  # per-USER: an attacker holding a stolen access token (but not the 2FA
  # code) can rotate IPs, so the IP throttle alone would not stop them from
  # grinding a single victim account — the user-keyed throttle closes that
  # gap; the IP throttle in turn stops one source hammering many accounts.
  #
  # Registered OUTSIDE the `unless Rails.env.test?` guard below (same
  # rationale as system_node_claim_by_ip just above, and its sibling spec
  # extensions/system/.../claim_throttle_spec.rb) so these two rules are
  # directly testable: the test-env fallback (999_999) below leaves every
  # other request spec that exercises disable/regenerate unaffected, and the
  # throttle spec opts in by stubbing rate_limiting_enabled?.
  throttle("two_factor_reauth_by_ip", limit: proc { rate_limiting_enabled? ? 5 : 999_999 }, period: 5.minutes) do |request|
    client_ip(request) if two_factor_reauth_path?(request)
  end

  throttle("two_factor_reauth_by_user", limit: proc { rate_limiting_enabled? ? 5 : 999_999 }, period: 5.minutes) do |request|
    if two_factor_reauth_path?(request)
      user = extract_user_from_request(request)
      "user:#{user.id}" if user
    end
  end

  unless Rails.env.test?
    # -----------------------------------------------------------------------
    # AUTHENTICATION ENDPOINTS (Strict limits - not tier-based)
    # -----------------------------------------------------------------------

    # Login attempts - IP-based
    throttle("auth_login_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("login_attempts_per_hour", 10) : 999_999 }, period: 1.hour) do |request|
      if request.path == "/api/v1/auth/login" && request.post?
        client_ip(request)
      end
    end

    # Login attempts - by email (prevent brute force on specific account)
    throttle("auth_login_by_email", limit: proc { rate_limiting_enabled? ? 5 : 999_999 }, period: 1.hour) do |request|
      if request.path == "/api/v1/auth/login" && request.post?
        begin
          body = JSON.parse(request.body.read)
          request.body.rewind
          body["email"]&.downcase
        rescue StandardError
          nil
        end
      end
    end

    # Registration attempts - IP-based
    throttle("auth_register_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("registration_attempts_per_hour", 5) : 999_999 }, period: 1.hour) do |request|
      if request.path == "/api/v1/auth/register" && request.post?
        client_ip(request)
      end
    end

    # Password reset requests - IP-based
    throttle("auth_password_reset_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("password_reset_attempts_per_hour", 3) : 999_999 }, period: 1.hour) do |request|
      if (request.path == "/api/v1/auth/forgot-password" || request.path == "/api/v1/auth/reset-password") && request.post?
        client_ip(request)
      end
    end

    # Email verification attempts - IP-based
    throttle("auth_email_verification_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("email_verification_attempts_per_hour", 10) : 999_999 }, period: 1.hour) do |request|
      if request.path.include?("/verify-email") || request.path.include?("/resend-verification")
        client_ip(request)
      end
    end

    # 2FA attempts - stricter limits
    throttle("auth_2fa_by_ip", limit: proc { rate_limiting_enabled? ? 5 : 999_999 }, period: 15.minutes) do |request|
      if request.path.include?("/two_factor") && request.post?
        client_ip(request)
      end
    end

    # -----------------------------------------------------------------------
    # TIER-BASED API RATE LIMITING (Account-level)
    # -----------------------------------------------------------------------

    # Account-level API throttling - per minute
    throttle("account_api_per_minute", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :api_requests_per_minute)
    }, period: 1.minute) do |request|
      if request.path.start_with?("/api/")
        account = extract_account_from_request(request)
        "account:#{account.id}" if account
      end
    end

    # Account-level API throttling - per hour
    throttle("account_api_per_hour", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :api_requests_per_hour)
    }, period: 1.hour) do |request|
      if request.path.start_with?("/api/")
        account = extract_account_from_request(request)
        "account:#{account.id}" if account
      end
    end

    # -----------------------------------------------------------------------
    # HEAVY OPERATIONS (AI, Reports, Exports)
    # -----------------------------------------------------------------------

    throttle("heavy_operations_by_account", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :heavy_requests_per_hour)
    }, period: 1.hour) do |request|
      heavy_paths = %w[/api/v1/ai_ /api/v1/workflows /api/v1/reports /api/v1/analytics /api/v1/data_export /api/v1/bulk_]
      if heavy_paths.any? { |path| request.path.start_with?(path) }
        account = extract_account_from_request(request)
        "heavy:account:#{account.id}" if account
      end
    end

    # -----------------------------------------------------------------------
    # FILE OPERATIONS
    # -----------------------------------------------------------------------

    throttle("file_uploads_by_account", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :file_uploads_per_hour)
    }, period: 1.hour) do |request|
      if request.path.match?(%r{^/api/v1/files?}) && request.post?
        account = extract_account_from_request(request)
        "files:account:#{account.id}" if account
      end
    end

    # -----------------------------------------------------------------------
    # WEBHOOK OPERATIONS
    # -----------------------------------------------------------------------

    throttle("webhook_requests_by_account", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :webhook_requests_per_minute)
    }, period: 1.minute) do |request|
      if request.path.start_with?("/webhooks/") || request.path.start_with?("/api/v1/webhook")
        account = extract_account_from_request(request)
        "webhooks:account:#{account.id}" if account
      end
    end

    # Incoming webhook throttling by IP (external services calling us)
    throttle("incoming_webhooks_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("webhook_requests_per_minute", 100) : 999_999 }, period: 1.minute) do |request|
      if request.path.start_with?("/webhooks/")
        client_ip(request)
      end
    end

    # -----------------------------------------------------------------------
    # WEBSOCKET CONNECTIONS
    # -----------------------------------------------------------------------

    throttle("websocket_connections_by_account", limit: proc { |request|
      return 999_999 unless rate_limiting_enabled?
      account = extract_account_from_request(request)
      tier_based_limit(account, :websocket_connections_per_minute)
    }, period: 1.minute) do |request|
      if request.path == "/cable" && request.get_header("HTTP_UPGRADE")&.downcase == "websocket"
        account = extract_account_from_request(request)
        "websocket:account:#{account.id}" if account
      end
    end

    # WebSocket by IP (fallback for unauthenticated)
    throttle("websocket_connections_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("websocket_connections_per_minute", Rails.env.development? ? 30 : 10) : 999_999 }, period: 1.minute) do |request|
      if request.path == "/cable" && request.get_header("HTTP_UPGRADE")&.downcase == "websocket"
        client_ip(request)
      end
    end

    # -----------------------------------------------------------------------
    # ADMIN/IMPERSONATION ENDPOINTS
    # -----------------------------------------------------------------------

    throttle("admin_impersonation_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("impersonation_attempts_per_hour", Rails.env.development? ? 50 : 5) : 999_999 }, period: 1.hour) do |request|
      if request.path.include?("/impersonation") || request.path.include?("/admin/users")
        client_ip(request)
      end
    end

    throttle("impersonation_by_user", limit: proc { rate_limiting_enabled? ? get_rate_limit("impersonation_attempts_per_hour", Rails.env.development? ? 50 : 5) : 999_999 }, period: 1.hour) do |request|
      if (request.path.include?("/impersonation") || request.path.include?("/admin/users")) && request.post?
        user = extract_user_from_request(request)
        "user:#{user.id}" if user
      end
    end

    # -----------------------------------------------------------------------
    # IP-BASED FALLBACK (for unauthenticated requests)
    # -----------------------------------------------------------------------

    throttle("api_requests_by_ip", limit: proc { rate_limiting_enabled? ? get_rate_limit("api_requests_per_minute", Rails.env.development? ? 1000 : 300) : 999_999 }, period: 15.minutes) do |request|
      if request.path.start_with?("/api/") && !extract_account_from_request(request)
        client_ip(request)
      end
    end

    # -----------------------------------------------------------------------
    # OAUTH ENDPOINTS (Based on application tier)
    # -----------------------------------------------------------------------

    throttle("oauth_token_requests", limit: proc { rate_limiting_enabled? ? 100 : 999_999 }, period: 1.hour) do |request|
      if request.path == "/oauth/token" && request.post?
        client_ip(request)
      end
    end

    throttle("oauth_authorize_requests", limit: proc { rate_limiting_enabled? ? 50 : 999_999 }, period: 1.hour) do |request|
      if request.path == "/oauth/authorize"
        client_ip(request)
      end
    end
  end

  # =========================================================================
  # BLOCKLIST RULES
  # =========================================================================

  # Block IPs that are clearly malicious
  blocklist("malicious_ips") do |request|
    # You can add known bad IPs here
    false # For now, don't block any IPs
  end

  # Block accounts that exceed extreme limits (10x normal)
  blocklist("extreme_abuse") do |request|
    next false unless rate_limiting_enabled?

    account = extract_account_from_request(request)
    next false unless account

    # Check if account has been flagged for abuse
    cache_key = "abuse_block:account:#{account.id}"
    Rails.cache.read(cache_key).present?
  end

  # =========================================================================
  # SAFELIST RULES
  # =========================================================================

  # Safelist trusted internal services
  safelist("internal_services") do |request|
    # Allow requests from localhost in development
    Rails.env.development? && [ "127.0.0.1", "::1" ].include?(client_ip(request))
  end

  # Safelist platform operators (system.admin). A compromised system.admin token
  # already implies full access, so throttling it adds little; and on a
  # self-hosted single-user instance the owner IS system.admin — customer tier
  # limits must not apply to them. Cached to avoid a permission lookup per
  # request; rescued so it can never error a request.
  safelist("admin_users") do |request|
    user = extract_user_from_request(request)
    next false unless user

    Rails.cache.fetch("rack_attack:admin:#{user.id}", expires_in: 5.minutes) do
      user.has_permission?("system.admin")
    end
  rescue StandardError
    false
  end

  # Safelist on-node agent traffic. /api/v1/system/node_api/* is gated by
  # mTLS or instance JWT (controller-level auth), so each request is bound
  # to a specific NodeInstance identity — billing tiers based on user
  # behavior don't apply. Throttling agent polls creates self-DOS at
  # higher fleet sizes (an account's own agents starved by its own tier).
  # Worker-api callers (POST /worker_api/*) have the same property.
  safelist("powernode_node_api") do |request|
    path = request.path.to_s
    # The anonymous device-claim endpoint has no credential at this point in
    # the device lifecycle, so the mTLS/JWT rationale above does NOT apply to
    # it. Keep it OUT of the safelist so the dedicated throttle below can cap
    # unbounded UnclaimedDevice creation. See audit 2026-06-09 finding F6-03.
    next false if path == "/api/v1/system/node_api/claim"

    path.start_with?("/api/v1/system/node_api/") ||
      path.start_with?("/api/v1/system/worker_api/") ||
      path.start_with?("/api/v1/system/federation_api/")
  end

  # Safelist specific API keys (e.g., system workers)
  #
  # IMP-24df1ec74489 — same key_hash -> key_digest column fix and digest
  # scheme fix as #extract_account_from_request above (see that method's
  # comment for the full trace). This rescue already failed open (not
  # safelisted; normal throttling still applies — the safe direction), but
  # logged nothing, which is exactly how the original column-name bug went
  # unnoticed: the safelist silently never matched, with zero trace. Now
  # logs at ERROR naming the reason, per the "a rate limiter that silently
  # stops limiting is the dangerous direction" principle.
  #
  # Review follow-up: reuses `ApiKey.find_by_key` (the model's own
  # digest-and-lookup pair) instead of a second hand-rolled
  # `find_by(key_digest: ApiKey.hash_key(...))` — a second copy of that
  # pairing is the same duplication that produced the original column/
  # scheme bug. And the CACHE key now uses `ApiKey.hash_key` (salted, same
  # scheme as the stored digest) instead of a bare `SHA256.hexdigest`:
  # nothing compares the two digests today so this was not exploitable as
  # written, but a bare hash of a live credential is still an unsalted
  # digest of secret material used as a cache key, and it was identical
  # across environments — a shared cache (e.g. dev and staging pointed at
  # one Redis) would collide on the same key and could serve one
  # environment's is_system_key verdict to another.
  safelist("system_api_keys") do |request|
    api_key = request.get_header("HTTP_X_API_KEY")
    next false unless api_key

    # Check if it's a system API key
    cache_key = "system_api_key:#{ApiKey.hash_key(api_key)}"
    Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
      key = ApiKey.find_by_key(api_key)
      key&.metadata&.dig("is_system_key") == true
    end
  rescue StandardError => e
    Rails.logger.error(
      "[RackAttack] system_api_keys safelist check failed — failing open (NOT safelisted; normal " \
      "throttling still applies to this request): #{e.class}: #{e.message}"
    )
    false
  end

  # =========================================================================
  # RESPONSE HANDLERS
  # =========================================================================

  # Custom response for throttled requests
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]

    # Try to get tier-specific info
    account = extract_account_from_request(request)
    tier = account ? RateLimiting::TieredService.tier_for_account(account) : :free
    tier_config = RateLimiting::TieredService.tier_config(tier)

    headers = {
      "Content-Type" => "application/json",
      "Retry-After" => match_data[:period].to_s,
      "X-RateLimit-Limit" => match_data[:limit].to_s,
      "X-RateLimit-Remaining" => "0",
      "X-RateLimit-Reset" => (now + match_data[:period]).to_s,
      "X-RateLimit-Tier" => tier.to_s,
      "X-RateLimit-Tier-Name" => tier_config[:name]
    }

    body = {
      success: false,
      error: "Too many requests",
      message: "Rate limit exceeded. Please try again later.",
      tier: tier.to_s,
      tier_name: tier_config[:name],
      retry_after: match_data[:period],
      upgrade_available: tier != :business && tier != :unlimited
    }.to_json

    [ 429, headers, [ body ] ]
  end

  # Custom response for blocked requests
  self.blocklisted_responder = lambda do |_request|
    [ 403, { "Content-Type" => "application/json" }, [ {
      success: false,
      error: "Forbidden",
      message: "Your request has been blocked due to excessive abuse."
    }.to_json ] ]
  end
end

# Enable Rack::Attack middleware in all environments except test
unless Rails.env.test?
  Rails.application.config.middleware.use Rack::Attack
end

# =========================================================================
# LOGGING & MONITORING
# =========================================================================

# Add logging for rate limit hits.
#
# NOTE THE RECEIVER. This block runs at TOP LEVEL (self == main), unlike the
# throttle/safelist blocks above, which close over `self == Rack::Attack`
# because they are written inside `class Rack::Attack`. So `client_ip` must be
# called on the class explicitly here — an unqualified call raises
# NoMethodError for main:Object.
#
# That is not a cosmetic distinction. This subscriber fires ONLY when a rule
# MATCHES, so the bug was invisible under normal traffic and appeared the
# instant a limit was hit: the NoMethodError propagated out of
# ActiveSupport::Notifications, through Rack::Attack, and into
# ProxySecurityValidator's catch-all, which returned a generic 500. Every
# throttle hit answered 500 instead of 429 and every blocklist hit 500 instead
# of 403 — with the real cause masked.
ActiveSupport::Notifications.subscribe("rack.attack") do |_name, _start, _finish, _request_id, payload|
  request = payload[:request]

  if request.env["rack.attack.matched"]
    match_type = request.env["rack.attack.match_type"]
    match_data = request.env["rack.attack.match_data"]

    case match_type
    when :throttle
      Rails.logger.warn(
        "[RateLimit] Throttled: " \
        "IP=#{Rack::Attack.client_ip(request)} " \
        "Path=#{request.path} " \
        "Rule=#{request.env['rack.attack.matched']} " \
        "Count=#{match_data[:count]}/#{match_data[:limit]} " \
        "Period=#{match_data[:period]}s"
      )
    when :blocklist
      Rails.logger.error(
        "[RateLimit] Blocked: " \
        "IP=#{Rack::Attack.client_ip(request)} " \
        "Path=#{request.path} " \
        "Rule=#{request.env['rack.attack.matched']}"
      )
    end
  end
end
