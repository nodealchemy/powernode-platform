# frozen_string_literal: true

module System
  # System::HostBridgeReaperJob — daily sweep over draining
  # Sdwan::HostBridge rows that have outlived the 24h grace window. Posts to
  # the server's worker_api endpoint; all real work happens server-side so
  # the worker doesn't import the SDWAN models directly. Pattern mirrors
  # System::IdentityReaperJob.
  #
  # IMP-53a5c597ec8c — without this sweep the drain window never closed. The
  # HostBridge state machine has no automatic edge out of `draining`, the
  # compiler's `compilable` scope INCLUDES draining, and the agent has no
  # report path that retires a bridge, so a non-forced release left the
  # bridge serving on the host indefinitely and never returned its short_id
  # to the per-host pool.
  class HostBridgeReaperJob < BaseJob
    sidekiq_options queue: "maintenance", retry: 3

    def execute
      logger.info "[System::HostBridgeReaperJob] starting 24h-grace sweep"

      response = BackendApiClient.new.post(
        "/api/v1/system/worker_api/sdwan/host_bridges/reap",
        {}
      )

      if response.is_a?(Hash) && response[:success] == false
        raise BackendApiClient::ApiError, "reap failed: #{response[:error] || 'unknown'}"
      end

      logger.info "[System::HostBridgeReaperJob] reaped bridges=#{extract(response, :reaped_bridges) || '?'}"
      response
    end

    private

    def extract(response, key)
      return nil unless response.is_a?(Hash)
      response.dig(:data, key) || response.dig("data", key.to_s)
    end
  end
end
