# frozen_string_literal: true

module Marketing
  class CampaignMetricsCollectionJob < BaseJob
    sidekiq_options queue: "marketing", retry: 3

    protected

    def execute
      log_info("Starting campaign metrics collection")

      # Fetch active campaigns from server
      response = with_api_retry do
        api_client.get("/api/v1/marketing/campaigns", { status: "active" })
      end

      campaigns = response["data"]["items"] || []
      log_info("Found active campaigns", count: campaigns.size)

      campaigns.each do |campaign|
        collect_metrics_for(campaign)
      rescue StandardError => e
        log_error("Failed to collect metrics for campaign", e, campaign_id: campaign["id"])
      end

      log_info("Campaign metrics collection completed", campaigns_processed: campaigns.size)
    end

    private

    def collect_metrics_for(campaign)
      log_info("Collecting metrics", campaign_id: campaign["id"], type: campaign["campaign_type"])

      # Fetch current statistics from server (aggregates from provider webhooks)
      metrics = with_api_retry do
        api_client.get("/api/v1/marketing/campaigns/#{campaign['id']}/statistics")
      end

      # Post aggregated metrics snapshot
      with_api_retry do
        api_client.post("/api/v1/internal/marketing/metrics", {
          campaign_id: campaign["id"],
          channel: campaign["campaign_type"],
          metrics: metrics.dig("data", "statistics") || {},
          metric_date: Date.current.to_s,
          collected_at: Time.current.iso8601
        })
      end
    end
  end
end
