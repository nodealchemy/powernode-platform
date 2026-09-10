# frozen_string_literal: true

# HYPOTHESIS RANKING FOR ONE INVESTIGATION (design §5.3, increment A6).
#
# ── WHY THIS IS A JOB AT ALL ────────────────────────────────────────────────
# Ranking asks a canonical agent to read the assembled evidence, which is an
# LLM call: seconds to minutes, a cost, and a failure mode (a provider outage)
# that has nothing to do with the request that triggered it. Design §5.3 says
# "in a worker job, never a request thread" and this is that job. The operator
# verb and the automatic triggers both return the moment the EVIDENCE is
# recorded; this is what turns an open investigation into a concluded one.
#
# ── HTTP ONLY ───────────────────────────────────────────────────────────────
# The worker holds no ActiveRecord model for `platform_investigations` and must
# not grow one: `server/` owns the agent, the skill gate and the confidence
# rule, and a worker-side copy of any of the three would be a second
# implementation that drifts. So the job does exactly what every sibling skill
# job does — POSTs to an internal endpoint and reports what came back.
#
# ── WHO ENQUEUES IT ─────────────────────────────────────────────────────────
# `Platform::InvestigationService#open!`, once, after the row is saved — so
# every door that opens an investigation (the MCP verb, the REST button, the
# automatic status emitter) reaches the ranker through one enqueue rather than
# three that can each forget.
#
# ── IT FAILS LOUDLY, ON PURPOSE ─────────────────────────────────────────────
# `POST /api/v1/internal/platform/investigations/:id/conclude` is the route
# this job calls; it exists. Any answer that is not a success raises here
# rather than logging a shrug and returning, because the open-fingerprint index
# releases only when a row LEAVES `open`: an investigation that never concludes
# both shows the operator a spinner with no explanation AND blocks every future
# investigation of that component.
class PlatformInvestigationJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 2

  CONCLUDE_PATH = "/api/v1/internal/platform/investigations/%<id>s/conclude"

  def execute(params = {})
    investigation_id = params["investigation_id"] || params[:investigation_id]
    if investigation_id.blank?
      log_error("PlatformInvestigationJob called with no investigation_id", ArgumentError.new("investigation_id required"))
      raise ArgumentError, "investigation_id is required"
    end

    log_info("Ranking investigation hypotheses", investigation_id: investigation_id)

    response = with_api_retry do
      api_client.post(format(CONCLUDE_PATH, id: investigation_id), {})
    end

    if response.is_a?(Hash) && response["success"]
      data = response["data"] || {}
      log_info("Investigation concluded",
               investigation_id: investigation_id,
               status: data.dig("investigation", "status"),
               hypotheses: Array(data.dig("investigation", "hypotheses")).size)
    else
      # NOT a warning. An investigation that never concludes is invisible on
      # the operator's screen, so the failure has to be loud enough to retry.
      log_error("Investigation ranking returned no result",
                StandardError.new("conclude returned #{response.inspect}"))
      raise StandardError, "Investigation #{investigation_id} did not conclude"
    end
  rescue StandardError => e
    log_error("Investigation ranking failed", e)
    raise
  end
end
