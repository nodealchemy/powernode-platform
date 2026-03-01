# frozen_string_literal: true

class AuthCleanupJob < BaseJob
  sidekiq_options queue: 'maintenance', retry: 2

  def execute(*_args)
    log_info("[AuthCleanup] Starting daily auth artifact cleanup")

    with_api_retry(max_attempts: 2) do
      api_client.post("/api/v1/internal/maintenance/cleanup_auth_artifacts")
    end

    log_info("[AuthCleanup] Auth artifact cleanup completed successfully")
  end
end
