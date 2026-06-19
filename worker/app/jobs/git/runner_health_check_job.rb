# frozen_string_literal: true

module Git
  class RunnerHealthCheckJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 2

    # Reconcile Git runner statuses against the provider (the authoritative
    # liveness source) on the server. This replaces the previous local-timeout
    # logic, which marked healthy *idle* runners offline whenever their
    # last_seen_at went stale — but last_seen_at reflects when we last polled the
    # provider, not a runner heartbeat, so idle-but-alive runners were falsely
    # taken offline and had to be manually re-synced.
    #
    # The server now syncs each runner from the provider (refreshing status +
    # last_seen_at) and marks offline only those the provider no longer reports.
    # See Devops::RunnerHealthService#reconcile_runner_statuses.
    def execute
      log_info "Starting Git runner health reconcile"

      response = api_client.post("/api/v1/internal/git/runners/reconcile")
      data = response.is_a?(Hash) ? (response["data"] || {}) : {}

      log_info "Runner health reconcile completed",
               synced: data["synced"], marked_offline: data["marked_offline"]
    end
  end
end
