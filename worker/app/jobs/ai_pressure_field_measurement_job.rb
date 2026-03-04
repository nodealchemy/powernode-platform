# frozen_string_literal: true

class AiPressureFieldMeasurementJob < BaseJob
  sidekiq_options queue: "ai_orchestration", retry: 1

  def execute
    log_info("Starting pressure field measurements")
    response = with_api_retry { api_client.post("/api/v1/internal/ai/coordination/measure_all_fields") }
    measured = response.dig("data", "measured") || 0
    log_info("Pressure field measurement complete", measured: measured)
  rescue StandardError => e
    log_error("Pressure field measurement failed", e)
    raise
  end
end
