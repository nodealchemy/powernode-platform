# frozen_string_literal: true

# G7 token-scope / permission-creep audit — the periodic trigger + alert for the
# credential/token scope review.
#
# Long-lived credentials drift toward over-provisioning (wildcard / admin /
# unrestricted scopes accumulate). The audit LOGIC is authoritative on the server
# (Ai::Security::TokenScopeAuditService), which reviews access scopes on active
# AI provider credentials and API tokens and flags the over-broad ones. This job
# calls that endpoint on a monthly schedule and ALERTS when anything is flagged.
#
# Why an endpoint and not a direct call: the worker is a standalone Sidekiq app
# that talks to the server over the internal HTTP API only — it cannot load the
# server's models/services — so the audit runs server-side where they live.
#
# CRYPTO-SAFE: the endpoint returns only subject ids + scope names; no secret or
# token value crosses the wire, so nothing sensitive is logged or broadcast here.
class AiTokenScopeAuditJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_orchestration', retry: 1

  AUDIT_PATH = "/api/v1/internal/ai/security/token_scope_audit"
  BROADCAST_PATH = "/api/v1/ai/autonomy/broadcast"

  def execute(*_args)
    log_info("[TokenScopeAudit] Running token-scope / permission-creep audit")

    response = api_client.post(AUDIT_PATH)

    unless response.is_a?(Hash) && response["success"]
      log_error("[TokenScopeAudit] Audit run failed", error: response.is_a?(Hash) ? response["error"] : response)
      return
    end

    data = response["data"] || {}
    count = data["over_provisioned_count"].to_i
    findings = data["findings"] || []

    if count.zero?
      log_info("[TokenScopeAudit] No over-provisioned credentials or tokens found")
    else
      alert_over_provisioning(count, findings)
    end
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("[TokenScopeAudit] Backend unavailable, skipping (will retry next cron)")
  rescue BackendApiClient::ApiError => e
    log_info("[TokenScopeAudit] Skipped: #{e.message}")
  end

  private

  def alert_over_provisioning(count, findings)
    subjects = Array(findings).map { |f| "#{f['subject_type']}##{f['subject_id']}" }

    # Primary alert: a worker error log is the established alert primitive
    # (centralised logging / monitoring picks it up), mirroring the gate-canary
    # and provider-health alerts. Only ids + scope names are present — no secrets.
    log_error(
      "[TokenScopeAudit] #{count} over-provisioned credential(s)/token(s) detected — review scopes",
      subjects: subjects.first(20).join(", ")
    )

    # Surface it to operators via the existing AI-orchestration health-alert
    # broadcast (the same worker→server path gate-canary / provider-health use).
    # Best-effort: a broadcast failure must NOT mask the log alert above.
    broadcast_over_provisioning(count, findings)
  end

  def broadcast_over_provisioning(count, findings)
    api_client.post(BROADCAST_PATH, {
      broadcast_type: "health_status",
      data: {
        source: "token_scope_audit",
        status: "warning",
        healthy: false,
        over_provisioned_count: count,
        findings: findings,
        message: "Token-scope audit flagged #{count} over-provisioned credential(s)/token(s) — review for permission creep."
      }
    })
  rescue StandardError => e
    log_warn("[TokenScopeAudit] Failed to broadcast over-provisioning alert: #{e.message}")
  end
end
