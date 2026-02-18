# frozen_string_literal: true

FactoryBot.define do
  factory :ai_behavioral_fingerprint, class: "Ai::BehavioralFingerprint" do
    account
    association :agent, factory: :ai_agent
    metric_name { "tool_call_rate" }
    baseline_mean { 5.0 }
    baseline_stddev { 1.0 }
    rolling_window_days { 7 }
    deviation_threshold { 2.0 }
    observation_count { 0 }
    anomaly_count { 0 }
    recent_observations { [] }
  end
end
