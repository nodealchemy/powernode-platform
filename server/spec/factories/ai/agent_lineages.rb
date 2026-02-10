# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_lineage, class: "Ai::AgentLineage" do
    account
    association :parent_agent, factory: :ai_agent
    association :child_agent, factory: :ai_agent
    spawn_reason { "programmatic_spawn" }
    spawned_at { Time.current }
    metadata { {} }

    trait :terminated do
      terminated_at { Time.current }
      termination_reason { "manual" }
    end

    trait :with_reason do
      transient do
        reason { "test_spawn" }
      end
      spawn_reason { reason }
    end
  end
end
