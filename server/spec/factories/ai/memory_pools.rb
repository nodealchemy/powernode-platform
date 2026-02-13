# frozen_string_literal: true

FactoryBot.define do
  factory :ai_memory_pool, class: "Ai::MemoryPool" do
    account
    pool_id { SecureRandom.uuid }
    sequence(:name) { |n| "Memory Pool #{n}" }
    pool_type { "shared_memory" }
    scope { "team" }
    data { {} }
    metadata { {} }
    access_control { {} }
    retention_policy { {} }
    version { 1 }
    data_size_bytes { 0 }
    persist_across_executions { false }

    trait :persistent do
      persist_across_executions { true }
    end

    trait :task_scoped do
      scope { "task" }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end
  end
end
