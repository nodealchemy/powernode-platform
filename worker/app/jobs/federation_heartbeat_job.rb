# frozen_string_literal: true

# FederationHeartbeatJob — periodic federation peer heartbeat sweep.
#
# Ticks every 60s via Sidekiq cron (declared in worker/config/sidekiq.yml
# under :federation_heartbeat). POSTs to the server's worker_api endpoint
# which invokes ::System::Federation::HeartbeatSweepService.run!. That
# service walks active platform federation peers whose last_heartbeat_at
# is stale (default >5min) and transitions them to `degraded` so operators
# notice the missed handshakes via dashboard alerts.
#
# Without this job the scheduler entry in sidekiq.yml resolves to an
# undefined constant; peers that lose connectivity stay in `active`
# indefinitely and the dashboard never flags the silence.
#
# Plan reference: Decentralized Federation §C + P3.5.
class FederationHeartbeatJob < BaseJob
  sidekiq_options queue: :system, retry: 1

  def execute(args = {})
    log_info "[FederationHeartbeatJob] Starting heartbeat sweep"

    response = api_client.post("/api/v1/system/worker_api/federation/heartbeat_sweep", {})

    if response["success"]
      data = response["data"] || {}
      log_info "[FederationHeartbeatJob] sweep complete: " \
               "swept=#{data['swept']} " \
               "degraded_ids=#{Array(data['degraded_ids']).size}"
      data
    else
      log_warn "[FederationHeartbeatJob] sweep API returned non-success: #{response.inspect}"
      { swept: 0, error: response["error"] }
    end
  rescue StandardError => e
    log_error "[FederationHeartbeatJob] sweep failed", e
    raise
  end
end
