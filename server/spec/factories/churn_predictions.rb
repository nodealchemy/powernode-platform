# frozen_string_literal: true

FactoryBot.define do
  factory :churn_prediction do
    account
    subscription { nil }
    churn_probability { 0.25 }
    risk_tier { "low" }
    confidence_score { 0.85 }
    predicted_churn_date { 90.days.from_now }
    days_until_churn { 90 }
    primary_risk_factor { nil }
    contributing_factors { [] }
    recommended_actions { [] }
    intervention_triggered { false }
    intervention_at { nil }
    model_version { "v1.0" }
    prediction_type { "monthly" }
    predicted_at { Time.current }

    trait :minimal_risk do
      churn_probability { 0.05 }
      risk_tier { "minimal" }
      days_until_churn { nil }
    end

    trait :low_risk do
      churn_probability { 0.25 }
      risk_tier { "low" }
      days_until_churn { 68 }
    end

    trait :medium_risk do
      churn_probability { 0.45 }
      risk_tier { "medium" }
      days_until_churn { 50 }
    end

    trait :high_risk do
      churn_probability { 0.65 }
      risk_tier { "high" }
      days_until_churn { 32 }
      primary_risk_factor { "usage_decline" }
      contributing_factors do
        [
          { "factor" => "usage_decline", "weight" => 0.35, "description" => "Usage dropped 40% in last 30 days" },
          { "factor" => "support_tickets", "weight" => 0.25, "description" => "3 unresolved tickets" }
        ]
      end
    end

    trait :critical_risk do
      churn_probability { 0.85 }
      risk_tier { "critical" }
      days_until_churn { 14 }
      primary_risk_factor { "no_activity" }
      contributing_factors do
        [
          { "factor" => "no_activity", "weight" => 0.40, "description" => "No login in 21 days" },
          { "factor" => "payment_failures", "weight" => 0.35, "description" => "2 consecutive failed payments" },
          { "factor" => "usage_decline", "weight" => 0.25, "description" => "Usage at 10% of peak" }
        ]
      end
      recommended_actions do
        [
          { "action" => "urgent_outreach", "priority" => "critical", "description" => "Immediate CSM contact" },
          { "action" => "offer_discount", "priority" => "high", "description" => "Offer 30% renewal discount" }
        ]
      end
    end

    trait :with_intervention do
      intervention_triggered { true }
      intervention_at { 1.day.ago }
    end

    trait :with_actions do
      recommended_actions do
        [
          { "action" => "proactive_outreach", "priority" => "high", "description" => "Schedule call with CSM" },
          { "action" => "offer_discount", "priority" => "medium", "description" => "Offer 20% renewal discount" }
        ]
      end
    end

    trait :with_subscription do
      association :subscription
    end
  end
end
