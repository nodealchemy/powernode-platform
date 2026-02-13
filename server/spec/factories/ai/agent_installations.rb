# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_installation, class: "Ai::AgentInstallation" do
    account
    association :agent_template, factory: :ai_agent_template
    status { "active" }
    license_type { "standard" }
    installed_version { "1.0.0" }
    custom_config { {} }
    usage_stats { {} }
    executions_count { 0 }
    total_cost_usd { 0.0 }

    trait :paused do
      status { "paused" }
    end

    trait :expired do
      status { "expired" }
      license_expires_at { 1.day.ago }
    end

    trait :cancelled do
      status { "cancelled" }
    end
  end
end
