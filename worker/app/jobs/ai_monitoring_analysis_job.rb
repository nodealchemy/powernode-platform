# frozen_string_literal: true

class AiMonitoringAnalysisJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[MonitoringAnalysis] Starting monitoring analysis")

    log_info("[MonitoringAnalysis] Checking predictive failure")
    with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/intelligence/monitoring/predictive_failure")
    end
    log_info("[MonitoringAnalysis] Predictive failure analysis completed")

    log_info("[MonitoringAnalysis] Checking SLA breach risk")
    with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/intelligence/monitoring/sla_breach_risk")
    end
    log_info("[MonitoringAnalysis] SLA breach risk analysis completed")

    log_info("[MonitoringAnalysis] Monitoring analysis completed successfully")
  end
end
