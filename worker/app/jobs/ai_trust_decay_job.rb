# frozen_string_literal: true

class AiTrustDecayJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[TrustDecay] Starting trust score decay processing")

    response = with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/autonomy/trust_scores/decay")
    end

    if response['success']
      data = response['data'] || []
      log_info("[TrustDecay] Trust score decay completed", decayed_count: data.size)
    else
      log_error("[TrustDecay] Decay endpoint returned error", error: response['error'])
    end
  end
end
