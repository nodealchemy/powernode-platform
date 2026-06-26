# frozen_string_literal: true

class AiSelfChallengeJob < BaseJob
  include AiSuspensionCheckConcern

  sidekiq_options queue: "ai_orchestration", retry: 1

  # account_id is resolved server-side at enqueue (from the challenge record) and
  # threaded through so the worker can honor the per-account kill switch. It is
  # optional for backward compatibility with any in-flight old-format jobs.
  def execute(challenge_id, account_id = nil)
    validate_required_params({ "challenge_id" => challenge_id }, "challenge_id")

    # Kill switch check — bail if AI activity is suspended for the account
    return if bail_if_ai_suspended!(account_id)

    log_info("Starting self-challenge processing", challenge_id: challenge_id)
    response = with_api_retry { api_client.post("/api/v1/internal/ai/self_challenges/process", { challenge_id: challenge_id }) }
    if response["success"]
      log_info("Self-challenge processing completed", result: response.dig("data"))
    else
      log_warn("Self-challenge processing returned no result")
    end
  rescue StandardError => e
    log_error("Self-challenge processing failed", e)
    raise
  end
end
