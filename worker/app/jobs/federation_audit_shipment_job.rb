# frozen_string_literal: true

# P9.2 — Per-peer audit log WORM shipment job.
#
# Ticks daily at 04:30 UTC via Sidekiq cron (declared in sidekiq.yml
# under :federation_audit_shipment). POSTs to the server's worker_api
# endpoint, which invokes ::Federation::AuditShipmentService.run!.
# That service sweeps every active federation peer's FleetEvent rows
# older than 30 days, seals them into a JSON-Lines export with
# sha256, and records the shipment receipt in
# system_federation_audit_shipments.
#
# Cadence rationale: daily, off-hours UTC. Audit data isn't latency-
# sensitive; the 30-day retention boundary is what matters. Running
# overnight keeps the seal I/O out of operator-business-hours patterns.
#
# Plan reference: Architectural Fix 2 + Social Contract #5 (audit
# transparency).
class FederationAuditShipmentJob < BaseJob
  sidekiq_options queue: :system, retry: 1

  def execute(args = {})
    log_info "[FederationAuditShipmentJob] starting WORM audit shipment sweep"

    body = {}
    body[:account_id] = args["account_id"] if args["account_id"]

    response = api_client.post(
      "/api/v1/system/worker_api/federation/audit_shipment",
      body
    )

    if response["success"]
      data = response["data"] || {}
      log_info "[FederationAuditShipmentJob] sweep complete: " \
               "peers=#{data['swept_peers']} shipped=#{data['shipped']} events=#{data['events']}"
      data
    else
      log_error "[FederationAuditShipmentJob] sweep failed: #{response['error']}"
      raise response["error"] || "federation_audit_shipment_failed"
    end
  end
end
