# frozen_string_literal: true

class AiNotificationDigestJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[NotificationDigest] Starting notification digest analysis")

    log_info("[NotificationDigest] Checking notification fatigue")
    with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/intelligence/notifications/fatigue_analysis")
    end
    log_info("[NotificationDigest] Fatigue analysis completed")

    log_info("[NotificationDigest] Generating digest recommendations")
    with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/intelligence/notifications/digest_recommendations")
    end
    log_info("[NotificationDigest] Digest recommendations completed")

    log_info("[NotificationDigest] Notification digest analysis completed successfully")
  end
end
