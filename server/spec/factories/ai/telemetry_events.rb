# frozen_string_literal: true

FactoryBot.define do
  factory :ai_telemetry_event, class: "Ai::TelemetryEvent" do
    account
    association :agent, factory: :ai_agent
    event_category { "action" }
    event_type { "tool_executed" }
    sequence_number { 0 }
    correlation_id { SecureRandom.uuid }
    event_data { { tool: "test", duration_ms: 100 } }
    outcome { "success" }
  end
end
