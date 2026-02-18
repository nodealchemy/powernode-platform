# frozen_string_literal: true

FactoryBot.define do
  factory :ai_shadow_execution, class: "Ai::ShadowExecution" do
    account
    association :agent, factory: :ai_agent
    action_type { "execute_tool" }
    shadow_input { { prompt: "test input" } }
    shadow_output { { result: "shadow result" } }
    reference_output { { result: "reference result" } }
    agreed { false }
    agreement_score { 0.5 }

    trait :agreed do
      reference_output { { result: "shadow result" } }
      agreed { true }
      agreement_score { 1.0 }
    end
  end
end
