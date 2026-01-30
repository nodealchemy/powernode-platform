# frozen_string_literal: true

FactoryBot.define do
  factory :background_job do
    sequence(:job_id) { |n| "job_#{SecureRandom.hex(12)}" }
    job_type { "TestJob" }
    status { "pending" }
    arguments { {} }
    priority { 0 }
    max_attempts { 25 }
    attempts { 0 }

    trait :pending do
      status { "pending" }
    end

    trait :in_progress do
      status { "in_progress" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      started_at { 5.minutes.ago }
      finished_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      started_at { 5.minutes.ago }
      failed_at { Time.current }
      error_message { "Job execution failed" }
    end

    trait :cancelled do
      status { "cancelled" }
      finished_at { Time.current }
    end
  end
end
