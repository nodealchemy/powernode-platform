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
      recipients = api_client.get("/api/v1/internal/marketing/campaigns/#{campaign['id']}/recipients")
      recipient_list = recipients.dig("data", "recipients") || []

      recipient_list.each_slice(100).with_index do |batch, index|
        Marketing::EmailBatchSendJob.perform_async(
          campaign['id'], index + 1, batch.map { |r| r['id'] }
        )
      end
    end

    def dispatch_social(campaign)
      log_info("Dispatching social campaign", campaign_id: campaign["id"])
      contents = api_client.get("/api/v1/marketing/campaigns/#{campaign['id']}/contents")
      (contents.dig("data", "contents") || []).each do |content|
        next unless content['social_account_id']

        Marketing::SocialMediaPostJob.perform_async(
          campaign['id'], content['social_account_id'], content['id']
        )
      end
    end

    def dispatch_multi_channel(campaign)
      channels = campaign["channels"] || []

      dispatch_email(campaign) if channels.include?("email")

      social_channels = channels & %w[twitter linkedin facebook instagram]
      if social_channels.any?
        dispatch_social(campaign)
      end
    end
  end
end
