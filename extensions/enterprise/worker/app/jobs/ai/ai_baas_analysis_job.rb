# frozen_string_literal: true

class AiBaasAnalysisJob < BaseJob
  sidekiq_options queue: 'ai_orchestration', retry: 1

  def execute(*_args)
    log_info("[BaasAnalysis] Starting BaaS analysis")

    log_info("[BaasAnalysis] Checking usage anomalies")
    with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/intelligence/baas/usage_anomalies")
    end
    log_info("[BaasAnalysis] Usage anomalies analysis completed")

    log_info("[BaasAnalysis] Checking tenant churn")
    with_api_retry(max_attempts: 2) do
      api_client.get("/api/v1/ai/intelligence/baas/tenant_churn")
    end
    log_info("[BaasAnalysis] Tenant churn analysis completed")

    log_info("[BaasAnalysis] BaaS analysis completed successfully")
  end
end
