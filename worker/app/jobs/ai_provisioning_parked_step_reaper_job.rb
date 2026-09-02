# frozen_string_literal: true

# Janitor for provisioning steps stranded on a settled approval
# (IMP-842b56d3a5d4).
#
# Ai::Provisioning::SkillCompositionRunner parks a step in `awaiting_approval`
# when its skill executor reaches the autonomy gate. Every caller of
# .resume_parked_step is SYNCHRONOUS with the approval decision, so a process
# death between the deferred operation settling and that call leaves the step
# parked forever: the runner forwards only `pending` successors and treats the
# parked status as in-flight, so nothing re-drives it and the mission stops
# behind one row until a human re-invokes the step.
#
# The server does the work — this is the cron that reaches it.
class AiProvisioningParkedStepReaperJob < BaseJob
  sidekiq_options queue: :maintenance, retry: 1

  def execute(_args = {})
    response = api_client.post("/api/v1/internal/ai/provisioning/parked_steps/reap")

    if response["success"]
      data = response["data"] || {}
      resumed = data["resumed"] || 0
      # Only speak when something was actually stranded: a quiet janitor and a
      # broken one look identical in the log otherwise.
      log_info "[AiProvisioningParkedStepReaperJob] Resumed #{resumed} stranded parked step(s)" if resumed.to_i > 0
      data
    else
      log_warn "[AiProvisioningParkedStepReaperJob] API returned error: #{response['error']}"
      { "examined" => 0, "resumed" => 0 }
    end
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info("[AiProvisioningParkedStepReaperJob] Backend unavailable, skipping (will retry next cron)")
  rescue BackendApiClient::ApiError => e
    log_info("[AiProvisioningParkedStepReaperJob] Skipped: #{e.message}")
  end
end
