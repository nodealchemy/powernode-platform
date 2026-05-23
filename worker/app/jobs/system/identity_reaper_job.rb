# frozen_string_literal: true

module System
  # System::IdentityReaperJob — daily sweep over draining ServiceUser
  # and ServiceGroup rows that have outlived the 24h grace window. Posts
  # to the server's worker_api endpoint; all real work happens server-
  # side so the worker doesn't import the identity models directly.
  # Pattern mirrors Sdwan::ReapUserDevicesJob.
  class IdentityReaperJob < BaseJob
    sidekiq_options queue: "maintenance", retry: 3

    def execute
      logger.info "[System::IdentityReaperJob] starting 24h-grace sweep"

      response = BackendApiClient.new.post(
        "/api/v1/system/worker_api/identity/reap",
        {}
      )

      if response.is_a?(Hash) && response[:success] == false
        raise BackendApiClient::ApiError, "reap failed: #{response[:error] || 'unknown'}"
      end

      reaped_users  = extract(response, :reaped_users)
      reaped_groups = extract(response, :reaped_groups)
      logger.info "[System::IdentityReaperJob] reaped users=#{reaped_users || '?'} groups=#{reaped_groups || '?'}"
      response
    end

    private

    def extract(response, key)
      return nil unless response.is_a?(Hash)
      response.dig(:data, key) || response.dig("data", key.to_s)
    end
  end
end
