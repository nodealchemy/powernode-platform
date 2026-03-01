# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_short_term_memory, class: "Ai::AgentShortTermMemory" do
    account
    association :agent, factory: :ai_agent
    session_id { SecureRandom.uuid }
    sequence(:memory_key) { |n| "key_#{n}" }
    memory_value { { data: "test_value" } }
    memory_type { "general" }
    ttl_seconds { 3600 }
    expires_at { 1.hour.from_now }
    access_count { 0 }
    last_accessed_at { Time.current }

    trait :expired do
      expires_at { 1.hour.ago }
    end

    trait :conversation do
      memory_type { "conversation" }
    end

    trait :tool_result do
      memory_type { "tool_result" }
    end

    trait :observation do
      memory_type { "observation" }
    end

    trait :frequently_accessed do
      access_count { 10 }
    end
  end
end
