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
# ── THE ENDPOINT DOES NOT EXIST YET, AND THIS JOB SAYS SO ───────────────────
# `POST /api/v1/internal/platform/investigations/:id/conclude` is the route
# this job calls. It is NOT in increment A6's partition (it needs a controller
# and a line in `config/routes.rb`, both owned elsewhere), so until it lands
# this job will get a 404 and FAIL LOUDLY rather than log a shrug and return.
# That is deliberate: a ranking job that quietly no-ops would leave every
# investigation open forever with nobody able to tell why.
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
