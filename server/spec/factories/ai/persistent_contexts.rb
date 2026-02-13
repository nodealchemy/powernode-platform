# frozen_string_literal: true

FactoryBot.define do
  factory :ai_persistent_context, class: "Ai::PersistentContext" do
    account
    sequence(:name) { |n| "Context #{n}" }
    context_id { SecureRandom.uuid }
    context_type { "agent" }
    scope { "account" }
    context_data { {} }
    metadata { {} }
    access_control { {} }
    retention_policy { {} }
    version { 1 }
    entry_count { 0 }
    access_count { 0 }
    data_size_bytes { 0 }

    trait :agent_scoped do
      context_type { "agent" }
      scope { "agent" }
    end

    trait :workflow_scoped do
      context_type { "workflow" }
      scope { "workflow" }
    end

    trait :archived do
      archived_at { Time.current }
    end
  end
end
