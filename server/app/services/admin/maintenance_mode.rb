# frozen_string_literal: true

require "ipaddr"
require "socket"

module Admin
  # Single persistent store + gate decision for platform-wide maintenance mode.
  #
  # Replaces THREE former writers, none of which ever gated a request:
  #   - AdminSettingsController#update wrote an AdminSetting("maintenance_mode")
  #     row nothing read.
  #   - Admin::Maintenance::MaintenanceController wrote
  #     Rails.application.config.maintenance_mode — per-process memory, lost on
  #     restart, invisible to every other Puma worker.
  #   - Two frontend-only toggles (AdminSettingsSecurityTabPage,
  #     PlatformConfiguration) posted to the generic admin_settings door above,
  #     same dead end.
  #
  # This is now the only writer. The only READERS are the two places a USER
  # principal is resolved — see `.blocked?` below for exactly which surfaces
  # that is (and, just as important, which surfaces it structurally is NOT).
  #
  # Backed by AdminSetting (the platform's DB-driven "System configuration
  # key-value store", docs/concepts/data-model.md) under a FRESH key
  # namespace ("maintenance.*", not the legacy "maintenance_mode" etc that the
  # first dead writer above used) — see db/migrate/20260924020000_... for why
  # reusing the old keys would have let a leftover "true" row from that dead
  # writer switch maintenance on the moment this shipped, on ANY deployment
  # that had ever touched the old (broken) admin-settings toggle.
  #
  # Reads are fronted by a short-TTL Rails.cache entry so the gate does not
  # hit Postgres on every request; the cache is invalidated on every write so
  # a toggle takes effect for every Puma worker within the TTL, not just the
  # process that wrote it.
  class MaintenanceMode
    ENABLED_KEY = "maintenance.enabled"
    MESSAGE_KEY = "maintenance.message"
    ENABLED_AT_KEY = "maintenance.enabled_at"
    ESTIMATED_COMPLETION_KEY = "maintenance.estimated_completion"
    BYPASS_IPS_KEY = "maintenance.bypass_ips"

    DEFAULT_MESSAGE = "System is under maintenance"
    CACHE_KEY = "maintenance_mode:status"
    CACHE_TTL = 5.seconds

    # Permissions exempt from the gate. admin.maintenance.mode is included
    # alongside the usual admin baseline (system.admin/admin.access, see
    # Role.assignment_admin?) so a user who can only manage maintenance mode
    # itself can never enable it and then be locked out of disabling it again.
    EXEMPT_PERMISSIONS = %w[system.admin admin.access admin.maintenance.mode].freeze

    TRUSTED_PROXIES_MESSAGE =
      "Bypass IPs require TRUSTED_PROXY_CIDRS to be configured (see docs/operations/trusted-proxy-cidrs.md). " \
      "Without a pinned reverse-proxy list, request.remote_ip cannot be trusted for a bypass decision — " \
      "any caller reaching this app directly (bypassing the real proxy) could forge X-Forwarded-For."

    InvalidBypassIp = Class.new(ArgumentError)

    class << self
      # -- Gate ---------------------------------------------------------------

      def enabled?
        status[:enabled]
      end

      # Cached read of the full status hash. A short TTL rather than no cache
      # at all: this runs on every USER-authenticated request (see `.blocked?`),
      # so an uncached DB read per request is not acceptable, but caching for
      # minutes would leave a just-toggled flag unenforced fleet-wide for the
      # whole window.
      def status
        Rails.cache.fetch(CACHE_KEY, expires_in: CACHE_TTL) { read_from_store }
      end

      # The ONLY gate decision this class makes: false (never blocked) when
      # maintenance is disabled, when `remote_ip` is on the configured bypass
      # list, or when the caller's permission check satisfies EXEMPT_PERMISSIONS
      # — true otherwise. Called from exactly two call sites, both of which
      # resolve a real Powernode USER as the request's principal:
      #   - Authentication#authenticate_request (server/app/controllers/concerns/
      #     authentication.rb), the `if @current_user` branch — REST API.
      #   - McpTokenAuthentication#authenticate_via_doorkeeper_token
      #     (server/app/controllers/concerns/mcp_token_authentication.rb) —
      #     MCP OAuth 2.1.
      # `permission_check` is the CALLER's own has_permission? — Authentication's
      # is delegation-aware (an account-switch session's authority comes from
      # the delegation, not the user's own roles); the MCP path uses the plain
      # User#has_permission? because Doorkeeper tokens never carry a delegation.
      # Resolving permissions here instead would silently drop that distinction
      # for one of the two callers — so this never does.
      #
      # Surfaces this NEVER runs against, by construction — none of them ever
      # reach either call site above:
      #   - Worker principals: JWT (Authentication#handle_worker_token) and
      #     mTLS-forwarded-cert (#authenticate_worker_via_forwarded_cert) — the
      #     standalone Sidekiq worker and Api::V1::Worker::* (worker_files,
      #     processing_jobs).
      #   - Internal::* (Api::V1::Internal::InternalBaseController) and the
      #     system extension's worker_api/node_api base controllers — all
      #     `skip_before_action :authenticate_request` and authenticate via
      #     their own mTLS/instance-JWT concern instead.
      #   - MCP instance/federation principals (authenticate_via_node_mtls,
      #     authenticate_via_federation_partner) — both explicitly set
      #     @current_user = nil before returning true.
      #   - The Doorkeeper OAuth token endpoint itself (/oauth/token, minting a
      #     new access token) — issues tokens, never resolves a request-scoped
      #     Powernode @current_user.
      #   - A2A tasks that authenticate as a worker or federation partner
      #     rather than a User — same reasoning as the worker/MCP-instance
      #     bullets above; they never touch either call site. BaaS is
      #     DIFFERENT: it authenticates by tenant API key, not as a worker or
      #     federation partner, and is intentionally ungated — a tenant's BaaS
      #     traffic is not a Powernode operator session and must keep working
      #     through a platform maintenance window.
      #   - Login/refresh/verify_2fa, inbound webhooks, health/status endpoints,
      #     and the public boot endpoints (config, extensions/ui, settings/public)
      #     — all `skip_before_action :authenticate_request`, so no @current_user
      #     is ever resolved for them to gate on. Deliberately ungated: blocking
      #     login would make a plain user's FIRST encounter with maintenance mode
      #     an opaque failure to sign in rather than a normal authenticated
      #     request that surfaces the maintenance screen.
      def blocked?(remote_ip = nil)
        return false unless enabled?
        return false if bypass_ip?(remote_ip)

        EXEMPT_PERMISSIONS.none? { |perm| yield(perm) }
      end

      # -- Bypass IPs -----------------------------------------------------------

      # False whenever TRUSTED_PROXY_CIDRS is unset — see #trusted_proxies_configured?
      # and TRUSTED_PROXIES_MESSAGE. Not just a write-time check: if the env var
      # is ever removed after bypass IPs were configured, matching fails closed
      # immediately rather than continuing to honor a now-untrustworthy remote_ip.
      def bypass_ip?(remote_ip)
        return false if remote_ip.blank?
        return false unless trusted_proxies_configured?

        addr = safe_addr(remote_ip)
        return false unless addr

        status[:bypass_ips].any? { |entry| bypass_entry_matches?(entry, addr) }
      end

      # -- Writes ---------------------------------------------------------------

      # Raises InvalidBypassIp (caller renders 422) rather than silently
      # dropping an unparseable entry or accepting a bypass list that can never
      # take effect — a bypass list an admin believes is active but that
      # silently lost an entry, or can never match, is a worse failure mode
      # than a rejected write.
      def enable!(message:, estimated_completion: nil, bypass_ips: [])
        bypass_ips = Array(bypass_ips).map(&:to_s)
        validate_bypass_ips!(bypass_ips)

        AdminSetting.set(ENABLED_KEY, true)
        set_raw_string(MESSAGE_KEY, message.presence || DEFAULT_MESSAGE)
        set_raw_string(ENABLED_AT_KEY, Time.current.iso8601)
        set_raw_string(ESTIMATED_COMPLETION_KEY, estimated_completion)
        AdminSetting.set(BYPASS_IPS_KEY, bypass_ips)
        run_after_commit { invalidate_cache! }
        # read_from_store, not status: the cache invalidation above is
        # deferred to commit (see run_after_commit), so `status`'s cached
        # read could still return the PRE-write value here — the caller
        # (the controller's response body) must see what was just written.
        read_from_store
      end

      def disable!
        AdminSetting.set(ENABLED_KEY, false)
        set_raw_string(MESSAGE_KEY, nil)
        set_raw_string(ENABLED_AT_KEY, nil)
        set_raw_string(ESTIMATED_COMPLETION_KEY, nil)
        AdminSetting.set(BYPASS_IPS_KEY, [])
        run_after_commit { invalidate_cache! }
        read_from_store
      end

      # Updates message/estimated_completion/bypass_ips WITHOUT touching
      # `enabled` or `enabled_at` — the Save action in the Mode tab routes
      # here (PATCH /admin/maintenance/mode), separate from the Toggle
      # action's POST (enable!/disable!). Two defects this fixes by
      # construction, not by special-casing:
      #   - Saving edits while maintenance is OFF used to go through
      #     disable!, which unconditionally wipes message/ETA/bypass_ips back
      #     to defaults — an admin staging a message before turning
      #     maintenance on would have it silently discarded.
      #   - Saving edits while maintenance is ON used to go through enable!,
      #     which unconditionally rewrites enabled_at to Time.current — every
      #     edit reset "maintenance has been on since" to now.
      # Neither of those fields is touched here, so neither defect can recur
      # regardless of which action a future caller adds.
      def update_fields!(message:, estimated_completion: nil, bypass_ips: [])
        bypass_ips = Array(bypass_ips).map(&:to_s)
        validate_bypass_ips!(bypass_ips)

        set_raw_string(MESSAGE_KEY, message.presence || DEFAULT_MESSAGE)
        set_raw_string(ESTIMATED_COMPLETION_KEY, estimated_completion)
        AdminSetting.set(BYPASS_IPS_KEY, bypass_ips)
        run_after_commit { invalidate_cache! }
        read_from_store
      end

      def invalidate_cache!
        Rails.cache.delete(CACHE_KEY)
      end

      private

      # Runs `block` once the SURROUNDING transaction commits (the maintenance
      # controller wraps state + audit-log writes in one), or immediately when
      # there is none (e.g. called directly from a spec). Deferring matters:
      # invalidating mid-transaction lets a concurrent reader repopulate the
      # cache with the PRE-write value before the transaction commits, leaving
      # that stale value cached for the rest of the TTL even after a
      # successful commit. ActiveRecord::Base.current_transaction returns a
      # NullTransaction (whose #after_commit runs the block synchronously)
      # when nothing is open, so this never silently no-ops.
      def run_after_commit(&block)
        ActiveRecord::Base.current_transaction.after_commit(&block)
      end

      def read_from_store
        {
          enabled: AdminSetting.get(ENABLED_KEY, false) == true,
          message: raw_string(MESSAGE_KEY).presence || DEFAULT_MESSAGE,
          enabled_at: raw_string(ENABLED_AT_KEY).presence,
          estimated_completion: raw_string(ESTIMATED_COMPLETION_KEY).presence,
          bypass_ips: Array(AdminSetting.get(BYPASS_IPS_KEY, [])).map(&:to_s),
          # Surfaced so the Maintenance Mode tab can disable/explain the
          # bypass-IP field instead of accepting input that enable! will
          # always reject with InvalidBypassIp.
          bypass_ips_supported: trusted_proxies_configured?
        }
      end

      # Message/estimated_completion are read AND written as plain strings,
      # deliberately bypassing AdminSetting.get/.set's JSON round-trip:
      # JSON.parse("123") is the integer 123, JSON.parse("true") the boolean
      # true, so an operator typing a numeric-looking message, or an
      # estimated_completion of e.g. "60", would otherwise have it silently
      # coerced to a non-string on the very next read.
      def raw_string(key)
        AdminSetting.find_by(key: key)&.value
      end

      def set_raw_string(key, value)
        # AdminSetting.set only skips its `.to_json` branch for an actual
        # String — nil must become "" here rather than pass through, or it
        # would be stored as the 4-character literal "null".
        AdminSetting.set(key, value.to_s)
      end

      # -- Bypass IP internals ----------------------------------------------

      # Driver decision: while TRUSTED_PROXY_CIDRS is unset, refuse EVERY
      # bypass entry outright — public or private — with a 422 explaining why,
      # rather than silently accepting a list that can never actually match
      # (bypass_ip? also refuses unconditionally in that state; see there).
      # Rails' DEFAULT trusted-proxy list (ActionDispatch::RemoteIp::TRUSTED_PROXIES)
      # trusts every loopback/private/link-local hop as a proxy, so left at
      # that default, request.remote_ip cannot be trusted for ANY bypass
      # decision: anything reaching this app directly from a private
      # address (another container on the same host/VPC, bypassing the real
      # reverse proxy) is treated as a trusted hop, and Rails honors its
      # X-Forwarded-For verbatim — which could forge a PUBLIC target just as
      # easily as a private one. Pinning trusted_proxies is what makes
      # request.remote_ip trustworthy at all, for any target.
      def validate_bypass_ips!(bypass_ips)
        return if bypass_ips.empty?
        raise InvalidBypassIp, TRUSTED_PROXIES_MESSAGE unless trusted_proxies_configured?

        invalid = bypass_ips.reject { |entry| valid_ip_or_cidr?(entry) }
        raise InvalidBypassIp, "invalid bypass IP/CIDR: #{invalid.join(', ')}" if invalid.any?
      end

      def valid_ip_or_cidr?(entry)
        IPAddr.new(entry)
        true
      rescue IPAddr::Error
        false
      end

      def safe_addr(value)
        IPAddr.new(value.to_s)
      rescue IPAddr::Error
        nil
      end

      # Whether the operator has pinned a NON-EMPTY trusted-proxy list —
      # checked against the PARSED result (Powernode::TrustedProxyCidrs.parse,
      # the same parser application.rb uses to build
      # config.action_dispatch.trusted_proxies), not the raw env var's mere
      # presence.
      #
      # N3: a var that IS set but entirely unparseable (e.g. "garbage") must
      # not report supported. application.rb only assigns
      # config.action_dispatch.trusted_proxies `if cidrs.any?` (see there), so
      # an all-invalid value leaves Rails' own default trusted-proxy list in
      # place — request.remote_ip is exactly as untrustworthy as if the var
      # were never set at all. Checking `.present?` on the raw env var missed
      # this: it reported "configured" for a value that produced zero pinned
      # proxies, which is the same false-open gap M3 exists to close, just
      # reached through a malformed value instead of a missing one.
      def trusted_proxies_configured?
        # Silent logger: this runs on every gated request while maintenance is
        # on, not just at boot — application.rb already warns about invalid
        # entries once, at startup; repeating that per-request would flood
        # the log for the entire duration of an incident.
        Powernode::TrustedProxyCidrs.parse(ENV["TRUSTED_PROXY_CIDRS"], logger: ->(_msg) {}).any?
      end

      def bypass_entry_matches?(entry, addr)
        range = safe_addr(entry)
        return false unless range

        range.include?(normalize_ipv4_mapped(addr))
      rescue IPAddr::Error
        false
      end

      # ::ffff:a.b.c.d (IPv4-mapped IPv6) must match a bare IPv4 bypass entry:
      # an IPv6-listening Puma behind some proxy configurations sees an IPv4
      # peer exactly this way.
      def normalize_ipv4_mapped(addr)
        return addr unless addr.ipv6? && addr.ipv4_mapped?

        IPAddr.new(addr.to_i & 0xffffffff, Socket::AF_INET)
      rescue IPAddr::Error, NoMethodError
        addr
      end
    end
  end
end
