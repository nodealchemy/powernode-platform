# frozen_string_literal: true

module Marketing
  class SocialMediaPostJob < BaseJob
    sidekiq_options queue: "marketing_social", retry: 3

    protected

    def execute(campaign_id, social_account_id, content_id)
      log_info("Posting to social media",
               campaign_id: campaign_id,
               social_account_id: social_account_id,
               content_id: content_id)

      # Fetch content and account details from server API
      content_data = with_api_retry do
        api_client.get("/api/v1/marketing/campaigns/#{campaign_id}/contents/#{content_id}")
      end

      content = content_data["data"]["content"]

      # Publish via server-side adapter
      result = with_api_retry do
        api_client.post("/api/v1/internal/marketing/campaigns/#{campaign_id}/publish", {
          channel: content['channel'], social_account_id: social_account_id,
          content_id: content_id
        })
      end

      log_info("Social media post published",
               campaign_id: campaign_id,
               channel: content["channel"],
               social_account_id: social_account_id,
               success: result["success"])
    end
  end
end
