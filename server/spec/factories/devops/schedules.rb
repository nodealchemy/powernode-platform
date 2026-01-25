# frozen_string_literal: true

FactoryBot.define do
  factory :devops_schedule, class: "Devops::Schedule" do
    association :pipeline, factory: :devops_pipeline
    association :created_by, factory: :user

    sequence(:name) { |n| "Schedule #{n}" }
    cron_expression { "0 0 * * *" }
    timezone { "UTC" }
    is_active { true }
    inputs { {} }
    last_run_at { nil }
    next_run_at { nil }

    trait :active do
      is_active { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :hourly do
      cron_expression { "0 * * * *" }
    end

    trait :daily do
      cron_expression { "0 0 * * *" }
    end

    trait :weekly do
      cron_expression { "0 0 * * 0" }
    end

    trait :monthly do
      cron_expression { "0 0 1 * *" }
    end

    trait :every_five_minutes do
      cron_expression { "*/5 * * * *" }
    end

    trait :workdays do
      cron_expression { "0 9 * * 1-5" }
    end

    trait :with_inputs do
      inputs do
        {
          "branch" => "main",
          "environment" => "production",
          "notify_on_completion" => true
        }
      end
    end

    trait :with_last_run do
      last_run_at { 1.hour.ago }
    end

    trait :with_next_run do
      next_run_at { 1.hour.from_now }
    end

    trait :due_for_execution do
      is_active { true }
      next_run_at { 1.minute.ago }
    end

    trait :us_eastern do
      timezone { "America/New_York" }
    end

    trait :us_pacific do
      timezone { "America/Los_Angeles" }
    end

    trait :europe do
      timezone { "Europe/London" }
    end
  end
end
