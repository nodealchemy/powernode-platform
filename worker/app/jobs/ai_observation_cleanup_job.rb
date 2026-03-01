# frozen_string_literal: true

class AiObservationCleanupJob < BaseJob
  sidekiq_options queue: :maintenance, retry: 1

  def execute(args = {})
    response = api_client.post("/api/v1/internal/ai/observations/cleanup")

    if response["success"]
      data = response["data"] || {}
      log_info "[AiObservationCleanupJob] Deleted #{data['expired_deleted']} expired, #{data['processed_deleted']} processed observations"
      data
    else
      log_warn "[AiObservationCleanupJob] API returned error: #{response['error']}"
      { expired_deleted: 0, processed_deleted: 0 }
    end
  end
end
