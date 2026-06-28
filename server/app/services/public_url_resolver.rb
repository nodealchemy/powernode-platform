# frozen_string_literal: true

# Resolves the public base URL used to build externally-shareable links (share links,
# download links, notification deep-links, etc.).
#
# CORE is single-tenant: it resolves one global base URL, DB-driven, in priority order:
#   1. Global platform default — SiteSetting.get("public_base_url")
#   2. ENV fallback          — APP_BASE_URL (deploy-time hint)
#   3. (none)                — returns "" so callers emit HOST-RELATIVE paths, which resolve
#                              against whatever host served the request (safe core-mode default)
#
# MULTI-TENANCY (per-account custom domains) is a BUSINESS feature and lives in the business
# extension — never in core. The business extension registers a tenant resolver via
# `PublicUrlResolver.register_tenant_resolver`; when present it is consulted FIRST with the
# account, so a tenant's domain wins. Core ships no per-account logic. This is the canonical seam
# for "what host are we publicly reachable at"; other base_url needs should resolve through here.
class PublicUrlResolver
  SETTING_KEY = "public_base_url"

  class << self
    # Business-extension seam: register a callable ->(account) { "https://tenant.example" | nil }.
    # Core leaves this nil (single-tenant); the business extension sets it at boot.
    def register_tenant_resolver(callable)
      @tenant_resolver = callable
    end

    def reset_tenant_resolver!
      @tenant_resolver = nil
    end

    # Scheme+host (no trailing slash), or "" when nothing is configured.
    def base_url(account: nil)
      candidate = tenant_base_url(account).presence ||
                  global_base_url.presence ||
                  ENV["APP_BASE_URL"].presence ||
                  ""
      candidate.to_s.chomp("/")
    end

    # Build an absolute URL when a base is configured, else a host-relative path.
    def url_for(path, account: nil)
      normalized = path.to_s.start_with?("/") ? path.to_s : "/#{path}"
      "#{base_url(account: account)}#{normalized}"
    end

    private

    # Delegates to the business extension's resolver when registered; core-mode → nil.
    def tenant_base_url(account)
      return nil unless @tenant_resolver && account

      @tenant_resolver.call(account)
    rescue StandardError => e
      Rails.logger.warn("PublicUrlResolver tenant resolver failed: #{e.class}: #{e.message}")
      nil
    end

    def global_base_url
      SiteSetting.get(SETTING_KEY)
    rescue StandardError
      nil
    end
  end
end
