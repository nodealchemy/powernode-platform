# frozen_string_literal: true

FactoryBot.define do
  factory :git_runner do
    association :git_provider_credential
    association :account

    sequence(:external_id) { |n| "runner#{n}" }
    sequence(:name) { |n| "Runner #{n}" }
    runner_scope { "repository" }
    status { "offline" }
    busy { false }
    labels { [ "self-hosted", "linux", "x64" ] }
    os { "Linux" }
    architecture { "x64" }
    version { "2.311.0" }
    total_jobs_run { 0 }
    successful_jobs { 0 }
    failed_jobs { 0 }
    last_seen_at { nil }

    trait :online do
      status { "online" }
      last_seen_at { 1.minute.ago }
    end

    trait :offline do
      status { "offline" }
      last_seen_at { 1.hour.ago }
    end

    trait :busy do
      status { "busy" }
      busy { true }
      last_seen_at { 30.seconds.ago }
    end

    trait :with_repository do
      association :git_repository
    end

    trait :organization_scope do
      runner_scope { "organization" }
      git_repository { nil }
    end

    trait :with_jobs do
      total_jobs_run { 100 }
      successful_jobs { 90 }
      failed_jobs { 10 }
    end
  end
end
