# frozen_string_literal: true

FactoryBot.define do
  factory :devops_repository, class: "Devops::Repository" do
    association :account
    association :provider, factory: :devops_provider

    sequence(:name) { |n| "test-repo-#{n}" }
    sequence(:full_name) { |n| "testuser/test-repo-#{n}" }
    default_branch { "main" }
    is_active { true }
    settings { {} }

    trait :inactive do
      is_active { false }
    end

    trait :synced do
      last_synced_at { 1.hour.ago }
      external_id { SecureRandom.hex(8) }
    end

    trait :with_protected_branches do
      settings { { "protected_branches" => [ "main", "release/*" ] } }
    end
  end
end
