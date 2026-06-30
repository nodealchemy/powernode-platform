# frozen_string_literal: true

# G11 gate-integrity canary — the periodic trigger + alert for the verification
# gate's self-check.
#
# Gates rot: a silently-broken verification gate (e.g. G1's real-test
# verification regressing to always-pass) would read green forever. The canary
# LOGIC is authoritative on the server (Ai::Ralph::GateCanaryService), feeding a
# fixed set of known-good and known-bad inputs through the live gate and checking
# every verdict still matches expectation. This job calls that endpoint on a
# schedule and ALERTS when the gate is broken.
#
# Why an endpoint and not a direct call: the worker is a standalone Sidekiq app
# that talks to the server over the internal HTTP API only — it cannot load the
# server's gate classes — so the canary runs server-side where the gate lives.
class AiGateCanaryJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_orchestration', retry: 1

  CANARY_PATH = "/api/v1/internal/ai/ralph_loops/gate_canary"
  BROADCAST_PATH = "/api/v1/ai/autonomy/broadcast"

  def execute(*_args)
    log_info("[GateCanary] Running verification-gate integrity canary")

    response = api_client.post(CANARY_PATH)

    unless response.is_a?(Hash) && response["success"]
      log_error("[GateCanary] Canary run failed", error: response.is_a?(Hash) ? response["error"] : response)
      return
    end

    data = response["data"] || {}
    checks = data["checks"] || []

    if data["healthy"]
      log_info("[GateCanary] Verification gate healthy", checks: checks.size)
    else
      alert_broken_gate(checks)
    end
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("[GateCanary] Backend unavailable, skipping (will retry next cron)")
  rescue BackendApiClient::ApiError => e
    log_info("[GateCanary] Skipped: #{e.message}")
  end

  private

  def alert_broken_gate(checks)
    failing = Array(checks).reject { |c| c["ok"] }
    names = failing.map { |c| c["name"] }

    # Primary alert: a worker error log is the established alert primitive
    # (centralised logging / monitoring picks it up), mirroring the CRITICAL
    # provider-health alerts in AiProviderHealthCheckJob.
    log_error(
      "[GateCanary] CRITICAL: verification gate is broken — verdicts no longer match expectation",
      failing_checks: names.join(", ")
    )

    # Surface it to operators via the existing AI-orchestration health-alert
    # broadcast (the same worker→server path provider-health uses). Best-effort:
    # a broadcast failure must NOT mask the log alert above.
    broadcast_broken_gate(failing)
  end

  def broadcast_broken_gate(failing)
    api_client.post(BROADCAST_PATH, {
      broadcast_type: "health_status",
      data: {
        source: "gate_canary",
        status: "critical",
        healthy: false,
        failing_checks: failing,
        message: "Verification gate integrity canary failed — a gate may be silently passing known-bad input."
      }
    })
  rescue StandardError => e
    log_warn("[GateCanary] Failed to broadcast gate-broken alert: #{e.message}")
  end
end
