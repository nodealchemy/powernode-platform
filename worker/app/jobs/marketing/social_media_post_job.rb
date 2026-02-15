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

      # Post via adapter (stub - actual posting handled server-side via adapter factory)
      log_info("Social media post dispatched",
               campaign_id: campaign_id,
               channel: content["channel"],
               social_account_id: social_account_id)

      # Report result back to server
      with_api_retry do
        api_client.post("/api/v1/internal/marketing/post_result", {
          campaign_id: campaign_id,
          social_account_id: social_account_id,
          content_id: content_id,
          status: "posted",
          posted_at: Time.current.iso8601
        })
      end
    end
  end
end
