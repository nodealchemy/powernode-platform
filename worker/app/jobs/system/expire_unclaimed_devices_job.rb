# frozen_string_literal: true

module System
  # Reaper for stale System::UnclaimedDevice rows. UnclaimedDevices have
  # a default 24h TTL; this job runs daily and deletes everything past
  # expires_at, emitting a single FleetEvent summarizing the batch.
  #
  # Without this, the unclaimed-devices queue grows unbounded as
  # operators forget about devices they never claimed (or devices that
  # bounced briefly during testing). Daily cadence is plenty — there's
  # no urgency to delete an expired row, just a hygiene need.
  #
  # All work happens via a server-side internal endpoint so the worker
  # doesn't need to import the System::UnclaimedDevice model. Pattern
  # mirrors System::ProcessModulePublicationJob (the prior async tail).
  #
  # Reference: docs/plans/wondrous-yawning-anchor.md §10.
  class ExpireUnclaimedDevicesJob < BaseJob
    sidekiq_options queue: 'maintenance', retry: 3

    def execute
      logger.info "[ExpireUnclaimedDevicesJob] starting reaper sweep"

      # Server endpoint does the actual delete + FleetEvent emit. Worker
      # is purely the cron driver. No body needed; server scopes by
      # current_account = nil and reaps across all accounts.
      response = BackendApiClient.new.post(
        "/api/v1/system/worker_api/unclaimed_devices/expire",
        {}
      )

      if response.is_a?(Hash) && response[:success] == false
        raise BackendApiClient::ApiError, "expire failed: #{response[:error] || 'unknown'}"
      end

      reaped = response.is_a?(Hash) ? response.dig(:data, :reaped_count) || response.dig("data", "reaped_count") : nil
      logger.info "[ExpireUnclaimedDevicesJob] reaped #{reaped || '?'} expired rows"
      response
    end
  end
end
