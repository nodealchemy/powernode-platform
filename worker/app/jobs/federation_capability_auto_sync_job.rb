# frozen_string_literal: true

# P9 — Auto-policy capability sweep job.
#
# Ticks every 5min via Sidekiq cron (declared in worker/config/sidekiq.yml
# under :federation_capability_auto_sync). POSTs to the server's
# worker_api endpoint, which invokes
# ::Federation::CapabilityAutoSyncService.run!. That service walks
# every FederationCapability whose policy is in the auto-flow set
# (auto_periodic, on_match_filter, auto_on_change) and dispatches the
# sync transport per row.
#
# Cadence rationale: 5min is the balance between operator-perceived
# freshness (resources sync into peers within ~5min of an update) and
# load on the federation_api endpoints. Operators who need tighter
# sync can ratchet down the cron or override per-capability via
# auto_on_change (callback-driven) on hot resource_kinds.
#
# Plan reference: P9 — auto-policy capabilities.
class FederationCapabilityAutoSyncJob < BaseJob
  sidekiq_options queue: :system, retry: 1

  def execute(args = {})
    log_info "[FederationCapabilityAutoSyncJob] starting capability auto-sync sweep"

    body = {}
    body[:account_id]          = args["account_id"]          if args["account_id"]
    body[:federation_peer_id]  = args["federation_peer_id"]  if args["federation_peer_id"]

    response = api_client.post(
      "/api/v1/system/worker_api/federation/capability_auto_sync",
      body
    )

    if response["success"]
      data = response["data"] || {}
      log_info "[FederationCapabilityAutoSyncJob] sweep complete: " \
               "swept=#{data['swept']} synced=#{data['synced']} failed=#{data['failed']}"
      data
    else
      log_error "[FederationCapabilityAutoSyncJob] sweep failed: #{response['error']}"
      raise response["error"] || "capability_auto_sync_failed"
    end
  end
end
