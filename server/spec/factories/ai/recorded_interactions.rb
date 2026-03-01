# frozen_string_literal: true

FactoryBot.define do
  factory :ai_recorded_interaction, class: "Ai::RecordedInteraction" do
    account
    association :sandbox, factory: :ai_sandbox
    recording_id { SecureRandom.uuid }
    interaction_type { "llm_request" }
    provider_type { "openai" }
    model_name { "gpt-4" }
    request_data { { "prompt" => "Test prompt" } }
    response_data { { "content" => "Test response" } }
    metadata { {} }
    tokens_input { 100 }
    tokens_output { 50 }
    cost_usd { 0.01 }
    latency_ms { 500 }
    recorded_at { Time.current }

    trait :tool_call do
      interaction_type { "tool_call" }
    end

    trait :api_call do
      interaction_type { "api_call" }
    end
  end
end
