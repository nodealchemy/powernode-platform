# frozen_string_literal: true

FactoryBot.define do
  factory :customer_health_score do
    account
    subscription { nil }
    overall_score { 75 }
    health_status { "healthy" }
    at_risk { false }
    risk_level { "low" }
    risk_factors { [] }
    trend_direction { "stable" }
    score_change_30d { 0 }
    engagement_score { 80 }
    payment_score { 90 }
    usage_score { 70 }
    support_score { 75 }
    tenure_score { 65 }
    calculated_at { Time.current }

    trait :thriving do
      overall_score { 90 }
      health_status { "thriving" }
      risk_level { "none" }
    end

    trait :at_risk do
      overall_score { 30 }
      health_status { "at_risk" }
      at_risk { true }
      risk_level { "high" }
      risk_factors { ["low_engagement", "payment_issues"] }
    end

    trait :critical do
      overall_score { 15 }
      health_status { "critical" }
      at_risk { true }
      risk_level { "critical" }
      risk_factors { ["no_activity", "payment_failures", "support_escalations"] }
    end

    trait :needs_attention do
      overall_score { 50 }
      health_status { "needs_attention" }
      risk_level { "medium" }
    end

    trait :improving do
      trend_direction { "improving" }
      score_change_30d { 15 }
    end

    trait :declining do
      trend_direction { "declining" }
      score_change_30d { -10 }
    end

    trait :with_subscription do
      association :subscription
    end
  end
end
