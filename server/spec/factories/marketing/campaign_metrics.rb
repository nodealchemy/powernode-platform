# frozen_string_literal: true

FactoryBot.define do
  factory :marketing_campaign_metric, class: "Marketing::CampaignMetric" do
    association :campaign, factory: :marketing_campaign
    channel { "email" }
    metric_date { Date.current }
    sends { 1000 }
    deliveries { 950 }
    opens { 300 }
    unique_opens { 250 }
    clicks { 100 }
    conversions { 20 }
    bounces { 50 }
    unsubscribes { 5 }
    impressions { 0 }
    engagements { 0 }
    reach { 0 }
    revenue_cents { 50_000 }
    cost_cents { 10_000 }
    custom_metrics { {} }

    trait :social do
      channel { "twitter" }
      sends { 0 }
      deliveries { 0 }
      opens { 0 }
      unique_opens { 0 }
      bounces { 0 }
      unsubscribes { 0 }
      impressions { 5000 }
      engagements { 500 }
      reach { 3000 }
    end

    trait :zero_metrics do
      sends { 0 }
      deliveries { 0 }
      opens { 0 }
      unique_opens { 0 }
      clicks { 0 }
      conversions { 0 }
      bounces { 0 }
      unsubscribes { 0 }
      impressions { 0 }
      engagements { 0 }
      reach { 0 }
      revenue_cents { 0 }
      cost_cents { 0 }
    end

    trait :high_performance do
      sends { 10_000 }
      deliveries { 9800 }
      opens { 4000 }
      unique_opens { 3500 }
      clicks { 2000 }
      conversions { 500 }
      bounces { 200 }
      unsubscribes { 10 }
      revenue_cents { 500_000 }
      cost_cents { 25_000 }
    end

    trait :yesterday do
      metric_date { Date.yesterday }
    end

    trait :last_week do
      metric_date { 1.week.ago.to_date }
    end
  end
end
