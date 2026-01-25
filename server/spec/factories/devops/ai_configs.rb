# frozen_string_literal: true

FactoryBot.define do
  factory :devops_ai_config, class: "Devops::AiConfig" do
    association :account
    association :created_by, factory: :user

    sequence(:name) { |n| "AI Config #{n}" }
    description { "Test AI configuration for DevOps pipelines" }
    config_type { "code_review" }
    provider { "openai" }
    model { "gpt-4" }
    status { "active" }

    max_tokens { 4096 }
    temperature { 0.7 }
    top_p { 1.0 }
    frequency_penalty { 0.0 }
    presence_penalty { 0.0 }
    timeout_seconds { 30 }

    system_prompt { {} }
    settings { {} }
    rate_limits { { "requests_per_minute" => 60, "tokens_per_minute" => 100_000 } }
    metadata { {} }

    total_requests { 0 }
    total_tokens { 0 }
    last_used_at { nil }

    is_default { false }
    is_active { true }

    trait :default do
      is_default { true }
    end

    trait :inactive do
      status { "inactive" }
      is_active { false }
    end

    trait :archived do
      status { "archived" }
    end

    trait :chat do
      config_type { "chat" }
      system_prompt do
        {
          "role" => "system",
          "content" => "You are a helpful assistant for DevOps workflows."
        }
      end
    end

    trait :completion do
      config_type { "completion" }
    end

    trait :embedding do
      config_type { "embedding" }
      model { "text-embedding-ada-002" }
      max_tokens { nil }
      temperature { nil }
    end

    trait :code_review do
      config_type { "code_review" }
      system_prompt do
        {
          "role" => "system",
          "content" => "You are an expert code reviewer. Analyze code for bugs, security issues, and best practices."
        }
      end
    end

    trait :code_generation do
      config_type { "code_generation" }
      system_prompt do
        {
          "role" => "system",
          "content" => "You are an expert software developer. Generate clean, well-documented code."
        }
      end
    end

    trait :anthropic do
      provider { "anthropic" }
      model { "claude-3-opus-20240229" }
    end

    trait :google do
      provider { "google" }
      model { "gemini-pro" }
    end

    trait :azure do
      provider { "azure" }
      model { "gpt-4-turbo" }
      settings do
        {
          "azure_endpoint" => "https://example.openai.azure.com",
          "api_version" => "2024-02-15-preview"
        }
      end
    end

    trait :with_usage do
      total_requests { 100 }
      total_tokens { 50_000 }
      last_used_at { 1.hour.ago }
    end

    trait :high_temperature do
      temperature { 1.5 }
    end

    trait :low_temperature do
      temperature { 0.1 }
    end

    trait :with_rate_limits do
      rate_limits do
        {
          "requests_per_minute" => 30,
          "tokens_per_minute" => 50_000,
          "requests_per_day" => 1000
        }
      end
    end
  end
end
