# frozen_string_literal: true

FactoryBot.define do
  factory :ai_template_usage_metric, class: "Ai::TemplateUsageMetric" do
    association :agent_template, factory: :ai_agent_template
    metric_date { Date.current }
    page_views { 0 }
    unique_visitors { 0 }
    new_installations { 0 }
    uninstallations { 0 }
    total_installations { 0 }
    active_installations { 0 }
    total_executions { 0 }
    total_reviews { 0 }
    new_reviews { 0 }
    gross_revenue { 0.0 }
    platform_commission { 0.0 }
    publisher_revenue { 0.0 }

    trait :with_traffic do
      page_views { 500 }
      unique_visitors { 200 }
      new_installations { 15 }
      total_installations { 100 }
      active_installations { 85 }
    end

    trait :with_revenue do
      gross_revenue { 150.00 }
      platform_commission { 45.00 }
      publisher_revenue { 105.00 }
    end
  end
end
