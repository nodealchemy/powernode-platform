# frozen_string_literal: true

class AiPricingSyncJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[PricingSync] Starting pricing sync")

    response = with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/ai/autonomy/pricing/sync")
    end

    data = response['data'] || {}
    log_info("[PricingSync] Pricing sync completed: synced=#{data['synced']} failed=#{data['failed']} source=#{data['source']}")

    if (data['errors'] || []).any?
      log_warn("[PricingSync] Sync had errors", errors: data['errors'])
    end
  end
end
