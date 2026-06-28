# frozen_string_literal: true

# Recurring continual-discovery poller for the Campaign Discovery & Delegation Control
# Plane. Asks the backend to scan standing improvement signals across active accounts and
# upsert deduped campaign proposals into the queue. All discovery + dedupe happens
# server-side; this job only triggers it on a cron. Mirrors AiCampaignLandSchedulerJob.
class AiCampaignDiscoveryJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute(_args = {})
    response = api_client.post("/api/v1/internal/ai/campaign_discovery/scan")
    data = response.is_a?(Hash) ? (response["data"] || response) : {}
    log_info "[AiCampaignDiscovery] #{data['proposals_created'].to_i} proposal(s) across " \
             "#{data['accounts_processed'].to_i} account(s)"
    { proposals_created: data["proposals_created"].to_i, accounts_processed: data["accounts_processed"].to_i }
  rescue Faraday::ConnectionFailed, Errno::ECONNREFUSED
    log_info "[AiCampaignDiscovery] backend unavailable, skipping (will retry next cron)"
    { skipped: true }
  rescue StandardError => e
    log_error "[AiCampaignDiscovery] failed", e
    raise
  end
end
