# frozen_string_literal: true

class AiMonitoringHealthCheckJob < BaseJob
  sidekiq_options retry: 3

  def execute(account_id)
    log_info("Running AI monitoring health check for account #{account_id}")

    begin
      # Call the backend API to get real-time metrics and broadcast them
      response = api_client.post("/api/v1/ai/monitoring/broadcast_metrics", {
        account_id: account_id
      })

      if response['success']
        log_info("Successfully broadcasted AI monitoring metrics for account #{account_id}")
      else
        log_error("Failed to broadcast AI monitoring metrics: #{response['error']}")
      end
      
      # Schedule the next health check in 30 seconds
      AiMonitoringHealthCheckJob.perform_in(30.seconds, account_id)
      
    rescue => e
      log_error("AI monitoring health check failed for account #{account_id}: #{e.message}")
      raise
    end
  end
end