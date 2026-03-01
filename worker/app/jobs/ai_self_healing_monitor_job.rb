# frozen_string_literal: true

class AiSelfHealingMonitorJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[SelfHealingMonitor] Starting self-healing monitor sweep")

    results = {}

    # Check stuck workflows
    begin
      response = api_client.post("/api/v1/internal/ai/self_healing/check_stuck_workflows")
      results[:stuck_workflows] = response['data'] if response['success']
    rescue StandardError => e
      log_error("[SelfHealingMonitor] Stuck workflow check failed: #{e.message}")
    end

    # Check degraded providers
    begin
      response = api_client.post("/api/v1/internal/ai/self_healing/check_degraded_providers")
      results[:degraded_providers] = response['data'] if response['success']
    rescue StandardError => e
      log_error("[SelfHealingMonitor] Degraded provider check failed: #{e.message}")
    end

    # Check orphaned executions
    begin
      response = api_client.post("/api/v1/internal/ai/self_healing/check_orphaned_executions")
      results[:orphaned_executions] = response['data'] if response['success']
    rescue StandardError => e
      log_error("[SelfHealingMonitor] Orphaned execution check failed: #{e.message}")
    end

    # Cross-system anomaly detection
    begin
      response = api_client.post("/api/v1/internal/ai/self_healing/check_anomalies")
      results[:anomalies] = response['data'] if response['success']
    rescue StandardError => e
      log_error("[SelfHealingMonitor] Anomaly check failed: #{e.message}")
    end

    log_info("[SelfHealingMonitor] Sweep completed", results: results.transform_values { |v| v.is_a?(Hash) ? v['count'] : v })
  end
end
