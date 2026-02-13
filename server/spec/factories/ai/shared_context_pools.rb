# frozen_string_literal: true

FactoryBot.define do
  factory :ai_shared_context_pool, class: "Ai::SharedContextPool" do
    association :workflow_run, factory: :ai_workflow_run
    pool_id { SecureRandom.uuid }
    pool_type { "shared_memory" }
    scope { "workflow" }
    context_data { {} }
    metadata { {} }
    access_control { {} }
    version { 1 }

    trait :task_scoped do
      scope { "task" }
    end

    trait :expired do
      expires_at { 1.day.ago }
    end
  end
end
