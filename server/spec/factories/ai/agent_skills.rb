# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_skill, class: "Ai::AgentSkill" do
    association :agent, factory: :ai_agent
    association :skill, factory: :ai_skill
    is_active { true }
    priority { 0 }

    trait :inactive do
      is_active { false }
    end

    trait :high_priority do
      priority { 1 }
    end

    trait :low_priority do
      priority { 10 }
    end
  end
end
