# frozen_string_literal: true

# FederationTrustBundleRefreshJob — periodic symmetric-peer CA-anchor refresh.
#
# Ticks hourly via Sidekiq cron (declared in worker/config/sidekiq.yml under
# :federation_trust_bundle_refresh). POSTs to the server's worker_api endpoint
# which invokes ::Federation::TrustBundleRefreshService.run!. That service
# re-fetches each symmetric peer's current CA bundle from its
# /federation_api/trust_bundle endpoint, updates trusted_ca_pem when the peer
# rotated its CA, and rewrites the Traefik client-auth bundle so the new anchor
# is honored at the handshake.
#
# Without this job, a symmetric peer that rotates its CA would have its new
# certs rejected until the next reverse-proxy boot.
#
# Federation mTLS Phase 2 (symmetric); SPIFFE bundle-endpoint refresh pattern.
class FederationTrustBundleRefreshJob < BaseJob
  sidekiq_options queue: :system, retry: 1

  def execute(args = {})
    log_info "[FederationTrustBundleRefreshJob] Starting trust-bundle refresh"

    response = api_client.post("/api/v1/system/worker_api/federation/trust_bundle_refresh", {})

    if response["success"]
      data = response["data"] || {}
      log_info "[FederationTrustBundleRefreshJob] refresh complete: " \
               "checked=#{data['checked']} updated=#{data['updated']} " \
               "failures=#{Array(data['failures']).size}"
      data
    else
      log_warn "[FederationTrustBundleRefreshJob] refresh API returned non-success: #{response.inspect}"
      { checked: 0, updated: 0, error: response["error"] }
    end
  rescue StandardError => e
    log_error "[FederationTrustBundleRefreshJob] refresh failed", e
    raise
  end
end
