# frozen_string_literal: true

module Sdwan
  # 90-day audit retention sweep for revoked Sdwan::UserDevice rows.
  # Slice 4 promised that revoking a user's VPN device leaves the Vault
  # entry intact for 90 days for audit purposes; this job is what makes
  # that promise real. Without it, revoked rows + their Vault entries
  # accumulate indefinitely.
  #
  # All real work happens via the server's worker_api endpoint so the
  # worker doesn't import the Sdwan::UserDevice model directly. Pattern
  # mirrors System::ExpireUnclaimedDevicesJob.
  #
  # Slice 5 (deferred reaper) of the SDWAN plan.
  class ReapUserDevicesJob < BaseJob
    sidekiq_options queue: 'maintenance', retry: 3

    def execute
      logger.info "[Sdwan::ReapUserDevicesJob] starting 90-day audit sweep"

      response = BackendApiClient.new.post(
        "/api/v1/system/worker_api/sdwan/reap_user_devices",
        {}
      )

      if response.is_a?(Hash) && response[:success] == false
        raise BackendApiClient::ApiError, "reap failed: #{response[:error] || 'unknown'}"
      end

      reaped = response.is_a?(Hash) ? (response.dig(:data, :reaped_count) || response.dig("data", "reaped_count")) : nil
      logger.info "[Sdwan::ReapUserDevicesJob] reaped #{reaped || '?'} aged-out user devices"
      response
    end
  end
end
