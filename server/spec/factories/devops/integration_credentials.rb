# frozen_string_literal: true

FactoryBot.define do
  factory :devops_integration_credential, class: 'Devops::IntegrationCredential' do
    association :account
    association :created_by_user, factory: :user

    sequence(:name) { |n| "Test Credential #{n}" }
    credential_type { "api_key" }
    is_active { true }
    validation_status { "valid" }
    scopes { [] }
    metadata { {} }
    consecutive_failures { 0 }

    # Set credentials via the model's credentials= method
    after(:build) do |credential|
      credential.credentials = { "api_key" => "test_key_#{SecureRandom.hex(8)}" }
    end

    trait :github_app do
      credential_type { "github_app" }
      after(:build) do |credential|
        credential.credentials = {
          "app_id" => "123456",
          "private_key" => "-----BEGIN RSA PRIVATE KEY-----\ntest_key\n-----END RSA PRIVATE KEY-----",
          "installation_id" => "789012"
        }
      end
    end

    trait :oauth2 do
      credential_type { "oauth2" }
      after(:build) do |credential|
        credential.credentials = {
          "access_token" => "test_access_token_#{SecureRandom.hex(8)}",
          "refresh_token" => "test_refresh_token_#{SecureRandom.hex(8)}",
          "token_type" => "bearer",
          "expires_in" => 3600
        }
      end
    end

    trait :bearer_token do
      credential_type { "bearer_token" }
      after(:build) do |credential|
        credential.credentials = { "token" => "test_bearer_#{SecureRandom.hex(8)}" }
      end
    end

    trait :basic_auth do
      credential_type { "basic_auth" }
      after(:build) do |credential|
        credential.credentials = {
          "username" => "testuser",
          "password" => "testpass123"
        }
      end
    end

    trait :expired do
      validation_status { "expired" }
      expires_at { 1.day.ago }
      is_active { false }
    end

    trait :invalid do
      validation_status { "invalid" }
      consecutive_failures { 3 }
      last_error { "Authentication failed" }
    end

    trait :inactive do
      is_active { false }
    end

    trait :with_scopes do
      scopes { %w[repo:read repo:write] }
    end

    trait :expiring_soon do
      expires_at { 3.days.from_now }
    end
  end
end
