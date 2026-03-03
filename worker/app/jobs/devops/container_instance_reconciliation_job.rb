# frozen_string_literal: true

module Devops
  class ContainerInstanceReconciliationJob < BaseJob
    sidekiq_options queue: "devops_default", retry: 2, dead: false

    def execute
      log_info "[ContainerReconciliation] Starting container instance reconciliation"

      response = api_client.post("/api/v1/internal/devops/maintenance/reconcile_instances")
      result = safe_parse_json(response.body)

      reconciled_count = result.dig("data", "reconciled_count") || 0
      timed_out_count = result.dig("data", "timed_out_count") || 0

      log_info "[ContainerReconciliation] Reconciled #{reconciled_count} stale instances, #{timed_out_count} timed out"

      increment_counter("container_reconciliation_run")
      track_cleanup_metrics(
        reconciled_instances: reconciled_count,
        timed_out_instances: timed_out_count
      )
    end
  end
end
