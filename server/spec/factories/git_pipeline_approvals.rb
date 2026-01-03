# frozen_string_literal: true

FactoryBot.define do
  factory :git_pipeline_approval do
    association :git_pipeline
    association :account

    sequence(:gate_name) { |n| "deployment-gate-#{n}" }
    environment { "production" }
    description { "Approval required for production deployment" }
    status { "pending" }
    expires_at { 24.hours.from_now }
    responded_at { nil }
    response_comment { nil }
    metadata { {} }
    required_approvers { [] }

    trait :pending do
      status { "pending" }
      responded_at { nil }
    end

    trait :approved do
      status { "approved" }
      responded_at { 1.hour.ago }
      response_comment { "Approved for deployment" }
      association :responded_by, factory: :user
    end

    trait :rejected do
      status { "rejected" }
      responded_at { 1.hour.ago }
      response_comment { "Rejected due to failing tests" }
      association :responded_by, factory: :user
    end

    trait :expired do
      status { "expired" }
      expires_at { 1.hour.ago }
      responded_at { Time.current }
    end

    trait :cancelled do
      status { "cancelled" }
      responded_at { Time.current }
    end

    trait :with_requester do
      association :requested_by, factory: :user
    end

    trait :expiring_soon do
      status { "pending" }
      expires_at { 30.minutes.from_now }
    end

    trait :with_required_approvers do
      required_approvers { [ "manager", "tech-lead" ] }
    end

    trait :staging do
      environment { "staging" }
    end

    trait :production do
      environment { "production" }
    end
  end
end
