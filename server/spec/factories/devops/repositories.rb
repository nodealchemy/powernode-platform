# frozen_string_literal: true

FactoryBot.define do
  factory :devops_repository, class: "Devops::GitRepository" do
    association :account
    association :provider, factory: :devops_provider

    sequence(:name) { |n| "test-repo-#{n}" }
    sequence(:full_name) { |n| "testuser/test-repo-#{n}" }
    sequence(:owner) { |n| "testuser" }
    sequence(:external_id) { |n| SecureRandom.hex(8) }
    default_branch { "main" }
    is_active { true }
    origin { "devops" }
    metadata { {} }

    trait :inactive do
      is_active { false }
    end

    trait :synced do
      last_synced_at { 1.hour.ago }
    end

    trait :with_protected_branches do
      metadata { { "protected_branches" => [ "main", "release/*" ] } }
    end
  end
end
