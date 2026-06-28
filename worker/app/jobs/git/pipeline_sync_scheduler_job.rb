# frozen_string_literal: true

module Git
  # Recurring trigger that keeps Devops::GitPipeline (CI status) populated.
  # The server enumerates active git repos and enqueues a PipelineSyncJob for
  # each (mirrors Git::RunnerHealthCheckJob → runners/reconcile). Without this,
  # GitPipeline stays empty and CI status is invisible to the platform (and to
  # the auto-land CiGate).
  class PipelineSyncSchedulerJob < BaseJob
    sidekiq_options queue: "services", retry: 1

    def execute(_args = {})
      resp = api_client.post("/api/v1/internal/git/repositories/sync_all_pipelines")
      enqueued = (resp.is_a?(Hash) ? (resp["data"] || resp) : {})["enqueued"]
      log_info "[PipelineSyncScheduler] enqueued #{enqueued} repo pipeline sync(s)"
      { enqueued: enqueued }
    rescue StandardError => e
      log_error "[PipelineSyncScheduler] failed", e
      raise
    end
  end
end
