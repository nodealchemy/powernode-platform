# frozen_string_literal: true

FactoryBot.define do
  factory :git_provider_credential do
    association :git_provider
    association :account
    association :user

    sequence(:name) { |n| "Git Credential #{n}" }
    auth_type { 'personal_access_token' }
    encrypted_credentials { Base64.strict_encode64({ 'access_token' => 'test_token_123' }.to_json) }
    encryption_key_id { 'test_key' }
    external_username { 'testuser' }
    external_user_id { 'user123' }
    external_avatar_url { nil }
    scopes { %w[repo read:user] }
    is_active { true }
    is_default { false }
    expires_at { nil }
    last_used_at { nil }
    last_test_at { nil }
    last_test_status { nil }
    last_error { nil }
    success_count { 0 }
    failure_count { 0 }
    consecutive_failures { 0 }

    trait :default do
      is_default { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :oauth do
      auth_type { 'oauth' }
      expires_at { 1.hour.from_now }
    end

    trait :expired do
      auth_type { 'oauth' }
      expires_at { 1.hour.ago }
    end

    trait :healthy do
      last_test_at { 10.minutes.ago }
      last_test_status { 'healthy' }
      last_error { nil }
      consecutive_failures { 0 }
      success_count { 10 }
    end

    trait :unhealthy do
      last_test_at { 10.minutes.ago }
      last_test_status { 'unhealthy' }
      last_error { 'Connection failed' }
      consecutive_failures { 3 }
      failure_count { 5 }
    end

    trait :disabled_by_failures do
      is_active { false }
      consecutive_failures { 5 }
      last_error { 'Too many failures' }
    end

    trait :github do
      association :git_provider, :github
      scopes { %w[repo read:user workflow] }
    end

    trait :gitlab do
      association :git_provider, :gitlab
      scopes { %w[api read_user read_repository] }
    end

    trait :gitea do
      association :git_provider, :gitea
      scopes { %w[repo user] }
    end

    factory :default_git_credential, traits: [:default, :healthy]
    factory :unhealthy_git_credential, traits: [:unhealthy]
  end
end
