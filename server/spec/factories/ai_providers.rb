# frozen_string_literal: true

FactoryBot.define do
  factory :ai_provider do
    account
    sequence(:name) { |n| "AI Provider #{n}" }
    sequence(:slug) { |n| "provider-#{n}" }
    provider_type { "custom" }
    description { "A test AI provider for #{name}" }
    api_base_url { "https://api.example.com/v1" }
    api_endpoint { "https://api.example.com/v1" }
    capabilities { [ "text_generation", "chat" ] }
    supported_models do
      [
        {
          "name" => "test-model-1",
          "id" => "test-model-1",
          "context_length" => 4096,
          "cost_per_token" => 0.001
        },
        {
          "name" => "test-model-2",
          "id" => "test-model-2",
          "context_length" => 8192,
          "cost_per_token" => 0.002
        }
      ]
    end
    configuration_schema do
      {
        "type" => "object",
        "properties" => {
          "api_key" => {
            "type" => "string",
            "description" => "API key for authentication"
          },
          "model" => {
            "type" => "string",
            "description" => "Model to use"
          }
        },
        "required" => [ "api_key", "model" ]
      }
    end
    default_parameters { {} }
    rate_limits { {} }
    pricing_info { {} }
    is_active { true }
    requires_auth { true }
    supports_streaming { false }
    supports_functions { false }
    supports_vision { false }
    supports_code_execution { false }
    documentation_url { nil }
    status_url { nil }
    sequence(:priority_order) { |n| n }
    metadata { {} }

    # Handle virtual attributes for tests
    transient do
      health_status { nil }
      last_health_check { nil }
      is_default { nil }
      configuration { nil }
    end

    after(:build) do |provider, evaluator|
      # Handle configuration attribute for both build and create
      if !evaluator.configuration.nil?
        provider.configuration = evaluator.configuration
      end
    end

    after(:create) do |provider, evaluator|
      # Set virtual attributes for test compatibility
      if evaluator.health_status
        provider.instance_variable_set(:@health_status_override, evaluator.health_status)
      end

      if evaluator.last_health_check
        provider.instance_variable_set(:@last_health_check, evaluator.last_health_check)
      end

      # Handle is_default attribute
      if !evaluator.is_default.nil?
        provider.is_default = evaluator.is_default
        provider.save! # Save to persist metadata changes
      end

      # Handle configuration attribute
      if !evaluator.configuration.nil?
        provider.configuration = evaluator.configuration
        # Only save if the provider is still valid after setting configuration
        provider.save! if provider.valid?
      end

      # Handle explicit nil last_health_check (never checked)
      if evaluator.last_health_check.nil? && !evaluator.health_status
        # Set the instance variable to nil to indicate never checked
        provider.instance_variable_set(:@last_health_check, nil)
        provider.instance_variable_set(:@never_checked, true)
        # Clear any health metrics that might have been set by callbacks
        provider.update_column(:metadata, (provider.metadata || {}).except('health_metrics'))
      elsif evaluator.health_status || evaluator.last_health_check
        success = evaluator.health_status == 'healthy'
        timestamp = evaluator.last_health_check || Time.current

        # Manually set the health metrics with custom timestamp
        provider.metadata = (provider.metadata || {}).merge(
          'health_metrics' => {
            'last_check_timestamp' => timestamp.iso8601,
            'last_check_success' => success,
            'consecutive_failures' => success ? 0 : 1,
            'response_time_ms' => 0.01
          }
        )
        provider.save!
      end
    end

    trait :active do
      is_active { true }
    end

    trait :inactive do
      is_active { false }
    end

    trait :with_streaming do
      supports_streaming { true }
    end

    trait :with_functions do
      supports_functions { true }
      capabilities { [ "text_generation", "chat", "function_calling" ] }
    end

    trait :with_vision do
      supports_vision { true }
      capabilities { [ "text_generation", "chat", "vision" ] }
    end

    trait :with_code_execution do
      supports_code_execution { true }
      capabilities { [ "text_generation", "chat", "code_execution" ] }
    end

    trait :openai do
      name { "OpenAI" }
      slug { "openai" }
      provider_type { "openai" }
      api_base_url { "https://api.openai.com/v1" }
      capabilities { [ "text_generation", "chat", "text_embedding" ] }
      supports_streaming { true }
      supports_functions { true }
      supports_vision { true }
      documentation_url { "https://platform.openai.com/docs" }
      status_url { "https://status.openai.com/" }
      supported_models do
        [
          {
            "name" => "gpt-3.5-turbo",
            "id" => "gpt-3.5-turbo",
            "context_length" => 4096,
            "cost_per_token" => 0.0015
          },
          {
            "name" => "gpt-4",
            "id" => "gpt-4",
            "context_length" => 8192,
            "cost_per_token" => 0.03
          },
          {
            "name" => "gpt-4-vision-preview",
            "id" => "gpt-4-vision-preview",
            "context_length" => 128000,
            "cost_per_token" => 0.01
          }
        ]
      end
      configuration_schema do
        {
          "type" => "object",
          "properties" => {
            "api_key" => {
              "type" => "string",
              "description" => "OpenAI API key"
            },
            "model" => {
              "type" => "string",
              "enum" => [ "gpt-3.5-turbo", "gpt-4", "gpt-4-vision-preview" ],
              "description" => "Model to use"
            }
          },
          "required" => [ "api_key", "model" ]
        }
      end
      default_parameters do
        {
          "temperature" => 0.7,
          "max_tokens" => 2000,
          "top_p" => 1.0
        }
      end
      rate_limits do
        {
          "requests_per_minute" => 3500,
          "tokens_per_minute" => 90000
        }
      end
    end

    trait :ollama do
      name { "Ollama" }
      slug { "ollama" }
      provider_type { "ollama" }
      api_base_url { "http://localhost:11434/api" }
      capabilities { [ "text_generation", "chat" ] }
      requires_auth { false }
      supports_streaming { true }
      documentation_url { "https://ollama.ai/docs" }
      supported_models do
        [
          {
            "name" => "llama2",
            "id" => "llama2",
            "context_length" => 4096,
            "cost_per_token" => 0.0
          },
          {
            "name" => "codellama",
            "id" => "codellama",
            "context_length" => 16384,
            "cost_per_token" => 0.0
          },
          {
            "name" => "mistral",
            "id" => "mistral",
            "context_length" => 8192,
            "cost_per_token" => 0.0
          }
        ]
      end
      configuration_schema do
        {
          "type" => "object",
          "properties" => {
            "base_url" => {
              "type" => "string",
              "description" => "Ollama server base URL",
              "default" => "http://localhost:11434"
            },
            "model" => {
              "type" => "string",
              "description" => "Model to use"
            }
          },
          "required" => [ "model" ]
        }
      end
      default_parameters do
        {
          "temperature" => 0.8,
          "top_k" => 40,
          "top_p" => 0.9
        }
      end
      priority_order { 1 }
    end

    trait :anthropic do
      name { "Anthropic" }
      slug { "anthropic" }
      provider_type { "anthropic" }
      api_base_url { "https://api.anthropic.com/v1" }
      capabilities { [ "text_generation", "chat" ] }
      supports_streaming { true }
      supports_vision { true }
      documentation_url { "https://docs.anthropic.com/" }
      status_url { "https://status.anthropic.com/" }
      supported_models do
        [
          {
            "name" => "claude-3-sonnet-20240229",
            "id" => "claude-3-sonnet-20240229",
            "context_length" => 200000,
            "cost_per_token" => 0.003
          },
          {
            "name" => "claude-3-opus-20240229",
            "id" => "claude-3-opus-20240229",
            "context_length" => 200000,
            "cost_per_token" => 0.015
          },
          {
            "name" => "claude-3-haiku-20240307",
            "id" => "claude-3-haiku-20240307",
            "context_length" => 200000,
            "cost_per_token" => 0.00025
          }
        ]
      end
      configuration_schema do
        {
          "type" => "object",
          "properties" => {
            "api_key" => {
              "type" => "string",
              "description" => "Anthropic API key"
            },
            "model" => {
              "type" => "string",
              "enum" => [ "claude-3-sonnet-20240229", "claude-3-opus-20240229", "claude-3-haiku-20240307" ],
              "description" => "Model to use"
            }
          },
          "required" => [ "api_key", "model" ]
        }
      end
      default_parameters do
        {
          "max_tokens" => 4000,
          "temperature" => 0.0
        }
      end
      rate_limits do
        {
          "requests_per_minute" => 1000,
          "tokens_per_minute" => 40000
        }
      end
    end

    # Additional provider traits for expanded functionality
    trait :image_generation do
      provider_type { "custom" }
      capabilities { [ "image_generation" ] }
      supported_models do
        [
          {
            "name" => "dall-e-3",
            "id" => "dall-e-3",
            "max_resolution" => "1024x1024",
            "cost_per_image" => 0.04
          }
        ]
      end
    end

    trait :embedding do
      provider_type { "custom" }
      capabilities { [ "text_embedding", "code_embedding" ] }
      supported_models do
        [
          {
            "name" => "text-embedding-ada-002",
            "id" => "text-embedding-ada-002",
            "dimensions" => 1536,
            "cost_per_token" => 0.0001
          }
        ]
      end
    end
  end
end
