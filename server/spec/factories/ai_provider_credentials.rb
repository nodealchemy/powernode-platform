# frozen_string_literal: true

FactoryBot.define do
  factory :ai_provider_credential do
    association :account
    association :ai_provider

    sequence(:name) { |n| "Test Credential #{n}" }
    credentials do
      {
        "api_key" => "test-api-key-#{SecureRandom.hex(16)}",
        "model" => "test-model"
      }
    end
    is_active { true }
    is_default { false }
    last_used_at { nil }

    trait :default do
      is_default { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :failed_test do
      last_used_at { 1.hour.ago }
      consecutive_failures { 3 }
      last_error { "Invalid API key" }
    end

    trait :successful_test do
      last_used_at { 10.minutes.ago }
      consecutive_failures { 0 }
      last_error { nil }
    end

    trait :openai do
      association :ai_provider, :openai
      name { "OpenAI Credentials" }
      credentials do
        {
          "api_key" => "sk-test#{SecureRandom.hex(20)}",
          "model" => "gpt-3.5-turbo"
        }
      end
    end

    trait :ollama do
      association :ai_provider, :ollama
      name { "Local Ollama" }
      credentials do
        {
          "base_url" => "http://localhost:11434",
          "model" => "llama2"
        }
      end
    end

    trait :anthropic do
      association :ai_provider, :anthropic
      name { "Anthropic Claude" }
      credentials do
        {
          "api_key" => "ant-test#{SecureRandom.hex(20)}",
          "model" => "claude-3-sonnet"
        }
      end
    end

    trait :with_encryption do
      after(:build) do |credential|
        # Simulate encrypted credentials
        raw_creds = JSON.parse(credential.credentials)
        credential.credentials = raw_creds.to_json
      end
    end

    # Factory for creating credentials with specific provider types
    factory :openai_credential, traits: [ :openai ]
    factory :ollama_credential, traits: [ :ollama ]
    factory :anthropic_credential, traits: [ :anthropic ]

    # Factory for default credentials
    factory :default_ai_credential, traits: [ :default, :successful_test ]

    # Factory for failed credentials
    factory :failed_ai_credential, traits: [ :failed_test ]
  end
end
