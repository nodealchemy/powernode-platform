# frozen_string_literal: true

FactoryBot.define do
  factory :marketplace_subscription, class: "Marketplace::Subscription" do
    association :account
    subscribable { association(:ai_workflow_template) }
    status { "active" }
    subscribed_at { Time.current }
    tier { "standard" }
    configuration { {} }
    metadata { {} }
    usage_metrics { {} }

    trait :active do
      status { "active" }
    end

    trait :paused do
      status { "paused" }
    end

    trait :cancelled do
      status { "cancelled" }
      cancelled_at { Time.current }
    end

    trait :expired do
      status { "expired" }
    end

    trait :free_tier do
      tier { "free" }
    end

    trait :premium_tier do
      tier { "premium" }
    end

    trait :business_tier do
      tier { "business" }
    end
  end
end
