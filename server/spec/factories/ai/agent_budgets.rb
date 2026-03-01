# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_budget, class: "Ai::AgentBudget" do
    account
    association :agent, factory: :ai_agent
    total_budget_cents { 10_000 }
    spent_cents { 0 }
    reserved_cents { 0 }
    currency { "USD" }
    period_type { "monthly" }
    period_start { Time.current.beginning_of_month }
    period_end { Time.current.end_of_month }
    metadata { {} }

    trait :partially_spent do
      spent_cents { 5_000 }
    end

    trait :nearly_exceeded do
      spent_cents { 9_500 }
    end

    trait :exceeded do
      spent_cents { 10_000 }
    end

    trait :with_reservations do
      reserved_cents { 2_000 }
    end

    trait :daily do
      period_type { "daily" }
      period_start { Time.current.beginning_of_day }
      period_end { Time.current.end_of_day }
    end

    trait :total do
      period_type { "total" }
      period_end { nil }
    end
  end
end
