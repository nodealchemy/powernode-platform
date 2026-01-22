# frozen_string_literal: true

FactoryBot.define do
  factory :devops_provider, class: "Devops::Provider" do
    association :account

    sequence(:name) { |n| "Test Provider #{n}" }
    provider_type { "github" }
    base_url { "https://github.com" }
    api_version { "v1" }
    is_active { true }
    is_default { false }
    capabilities { %w[repositories pipelines] }
    configuration { {} }

    trait :github do
      provider_type { "github" }
      base_url { "https://github.com" }
    end

    trait :gitlab do
      provider_type { "gitlab" }
      base_url { "https://gitlab.com" }
    end

    trait :gitea do
      provider_type { "gitea" }
      base_url { "https://gitea.example.com" }
    end

    trait :jenkins do
      provider_type { "jenkins" }
      base_url { "https://jenkins.example.com" }
    end

    trait :default do
      is_default { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :healthy do
      health_status { "healthy" }
      last_health_check_at { 1.minute.ago }
    end
  end
end
