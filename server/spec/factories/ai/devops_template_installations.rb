# frozen_string_literal: true

FactoryBot.define do
  factory :ai_devops_template_installation, class: "Ai::DevopsTemplateInstallation" do
    association :account
    association :devops_template, factory: :ai_devops_template
    association :installed_by, factory: :user

    status { "active" }
    installed_version { "1.0.0" }
    custom_config { {} }
    variable_values { {} }
    execution_count { 0 }
    success_count { 0 }
    failure_count { 0 }

    trait :active do
      status { "active" }
    end

    trait :paused do
      status { "paused" }
    end

    trait :disabled do
      status { "disabled" }
    end

    trait :pending_update do
      status { "pending_update" }
    end

    trait :with_workflow do
      association :created_workflow, factory: :ai_workflow
    end

    trait :with_executions do
      execution_count { 50 }
      success_count { 45 }
      failure_count { 5 }
      last_executed_at { 1.hour.ago }
    end

    trait :high_success_rate do
      execution_count { 100 }
      success_count { 98 }
      failure_count { 2 }
      last_executed_at { 30.minutes.ago }
    end

    trait :high_failure_rate do
      execution_count { 50 }
      success_count { 20 }
      failure_count { 30 }
      last_executed_at { 2.hours.ago }
    end

    trait :never_executed do
      execution_count { 0 }
      success_count { 0 }
      failure_count { 0 }
      last_executed_at { nil }
    end

    trait :with_custom_config do
      custom_config do
        {
          "notifications" => { "slack_channel" => "#devops" },
          "thresholds" => { "max_issues" => 10 }
        }
      end
    end

    trait :with_variable_values do
      variable_values do
        {
          "target_branch" => "develop",
          "severity_threshold" => "high"
        }
      end
    end

    trait :outdated do
      installed_version { "0.9.0" }
      status { "pending_update" }
    end
  end
end
