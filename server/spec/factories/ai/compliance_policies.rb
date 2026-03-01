# frozen_string_literal: true

FactoryBot.define do
  factory :ai_compliance_policy, class: "Ai::CompliancePolicy" do
    account
    association :created_by, factory: :user
    sequence(:name) { |n| "Compliance Policy #{n}" }
    description { Faker::Lorem.paragraph }
    policy_type { "data_access" }
    status { "active" }
    enforcement_level { "warn" }
    priority { 0 }
    is_system { false }
    is_required { false }
    conditions { {} }
    applies_to { {} }
    actions { {} }
    exceptions { [] }
    violation_count { 0 }

    trait :draft do
      status { "draft" }
    end

    trait :active do
      status { "active" }
      activated_at { Time.current }
    end

    trait :disabled do
      status { "disabled" }
    end

    trait :archived do
      status { "archived" }
    end

    trait :system do
      is_system { true }
    end

    trait :required do
      is_required { true }
    end

    trait :blocking do
      enforcement_level { "block" }
    end

    trait :logging do
      enforcement_level { "log" }
    end

    trait :require_approval do
      enforcement_level { "require_approval" }
    end

    trait :data_access do
      policy_type { "data_access" }
    end

    trait :model_usage do
      policy_type { "model_usage" }
    end

    trait :rate_limit do
      policy_type { "rate_limit" }
      conditions do
        {
          "requests_per_minute" => { "max" => 100 },
          "requests_per_hour" => { "max" => 1000 }
        }
      end
    end

    trait :cost_limit do
      policy_type { "cost_limit" }
      conditions do
        {
          "daily_cost_usd" => { "max" => 100 },
          "monthly_cost_usd" => { "max" => 1000 }
        }
      end
    end

    trait :with_violations do
      after(:create) do |policy|
        create_list(:ai_policy_violation, 3, policy: policy, account: policy.account)
      end
    end

    trait :high_priority do
      priority { 100 }
    end
  end
end
