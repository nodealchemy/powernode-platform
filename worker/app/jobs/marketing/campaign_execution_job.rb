# frozen_string_literal: true

module Marketing
  class CampaignExecutionJob < BaseJob
    sidekiq_options queue: "marketing", retry: 3

    protected

    def execute(campaign_id)
      log_info("Executing campaign", campaign_id: campaign_id)

      campaign_data = api_client.get("/api/v1/marketing/campaigns/#{campaign_id}")
      campaign = campaign_data["data"]["campaign"]

      case campaign["campaign_type"]
      when "email"
        dispatch_email(campaign)
      when "social"
        dispatch_social(campaign)
      when "multi_channel"
        dispatch_multi_channel(campaign)
      else
        log_warn("Unknown campaign type", campaign_type: campaign["campaign_type"])
      end

      log_info("Campaign execution dispatched", campaign_id: campaign_id, type: campaign["campaign_type"])
    end

    private

    def dispatch_email(campaign)
      log_info("Dispatching email campaign", campaign_id: campaign["id"])
      # Would enqueue EmailBatchSendJob for each batch
    end

    def dispatch_social(campaign)
      log_info("Dispatching social campaign", campaign_id: campaign["id"])
      # Would enqueue SocialMediaPostJob for each platform
    end

    def dispatch_multi_channel(campaign)
      channels = campaign["channels"] || []

      dispatch_email(campaign) if channels.include?("email")

      social_channels = channels & %w[twitter linkedin facebook instagram]
      social_channels.each do |channel|
        log_info("Dispatching social post", campaign_id: campaign["id"], channel: channel)
        # Would enqueue SocialMediaPostJob per channel
      end
    end
  end
end
