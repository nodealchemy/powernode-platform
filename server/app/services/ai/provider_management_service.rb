# frozen_string_literal: true

class Ai::ProviderManagementService
  # Custom exception classes
  class ValidationError < StandardError; end
  class CredentialError < StandardError; end

  # Include extracted provider testing modules (instance-level)
  include ProviderTesting::Initialization
  include ProviderTesting::ConnectionTesting
  include ProviderTesting::HealthChecks
  include ProviderTesting::LoadTesting
  include ProviderTesting::ProviderAdapters
  include ProviderTesting::Reporting

  # Include extracted per-provider sync modules (class-level via class_methods)
  include Ai::Providers::Sync::Ollama
  include Ai::Providers::Sync::Openai
  include Ai::Providers::Sync::Anthropic
  include Ai::Providers::Sync::Google
  include Ai::Providers::Sync::Azure
  include Ai::Providers::Sync::Groq
  include Ai::Providers::Sync::Grok
  include Ai::Providers::Sync::Mistral
  include Ai::Providers::Sync::Cohere
  include Ai::Providers::Sync::Generic

  # Include decomposed concern modules
  include ProviderSpecs
  include CredentialValidation
  include ModelSync

  # Cache TTLs for model sync
  PROVIDER_MODELS_CACHE_TTL = 24.hours
  PROVIDER_USAGE_CACHE_TTL = 15.minutes

  # Model pricing per 1K tokens (in USD) - Updated Feb 2026
  # Authoritative reference used during syncs to populate cost_per_1k_tokens in supported_models
  MODEL_PRICING = {
    # OpenAI (Feb 2026)
    "gpt-4.1"                    => { "input" => 0.002,   "output" => 0.008,   "cached_input" => 0.0005,  "tier" => "premium" },
    "gpt-4.1-mini"               => { "input" => 0.0004,  "output" => 0.0016,  "cached_input" => 0.0001,  "tier" => "standard" },
    "gpt-4.1-nano"               => { "input" => 0.0001,  "output" => 0.0004,  "cached_input" => 0.000025, "tier" => "economy" },
    "o3"                         => { "input" => 0.002,   "output" => 0.008,   "cached_input" => 0.0005,  "tier" => "premium" },
    "o4-mini"                    => { "input" => 0.0011,  "output" => 0.0044,  "cached_input" => 0.000275, "tier" => "standard" },
    "gpt-4o"                     => { "input" => 0.0025,  "output" => 0.01,    "cached_input" => 0.00125, "tier" => "standard" },
    "gpt-4o-mini"                => { "input" => 0.00015, "output" => 0.0006,  "cached_input" => 0.000075, "tier" => "economy" },
    "gpt-4-turbo"                => { "input" => 0.01,    "output" => 0.03,    "cached_input" => 0.005,   "tier" => "premium" },
    "gpt-3.5-turbo"              => { "input" => 0.0005,  "output" => 0.0015,  "cached_input" => 0.00025, "tier" => "economy" },
    # Anthropic (Feb 2026)
    "claude-opus-4-6"            => { "input" => 0.005,   "output" => 0.025,   "cached_input" => 0.0005,  "tier" => "premium" },
    "claude-opus-4-5"            => { "input" => 0.005,   "output" => 0.025,   "cached_input" => 0.0005,  "tier" => "premium" },
    "claude-sonnet-4-5"          => { "input" => 0.003,   "output" => 0.015,   "cached_input" => 0.0003,  "tier" => "standard" },
    "claude-sonnet-4"            => { "input" => 0.003,   "output" => 0.015,   "cached_input" => 0.0003,  "tier" => "standard" },
    "claude-haiku-4-5"           => { "input" => 0.001,   "output" => 0.005,   "cached_input" => 0.0001,  "tier" => "economy" },
    "claude-3-5-sonnet"          => { "input" => 0.003,   "output" => 0.015,   "cached_input" => 0.0003,  "tier" => "standard" },
    "claude-3-5-haiku"           => { "input" => 0.0008,  "output" => 0.004,   "cached_input" => 0.00008, "tier" => "economy" },
    "claude-3-haiku-20240307"    => { "input" => 0.00025, "output" => 0.00125, "cached_input" => 0.00003, "tier" => "economy" },
    "claude-3-sonnet-20240229"   => { "input" => 0.003,   "output" => 0.015,   "cached_input" => 0.0003,  "tier" => "standard" },
    "claude-3-opus-20240229"     => { "input" => 0.015,   "output" => 0.075,   "cached_input" => 0.0015,  "tier" => "premium" },
    # X.AI (Grok)
    "grok-3"                     => { "input" => 0.003,   "output" => 0.015,   "cached_input" => 0.0003,  "tier" => "premium" },
    "grok-3-mini"                => { "input" => 0.0003,  "output" => 0.0005,  "cached_input" => 0.00003, "tier" => "economy" },
    "grok-3-mini-fast"           => { "input" => 0.0001,  "output" => 0.0004,  "cached_input" => 0.00001, "tier" => "economy" },
    "grok-3-fast"                => { "input" => 0.005,   "output" => 0.025,   "cached_input" => 0.0005,  "tier" => "premium" },
    "grok-2"                     => { "input" => 0.002,   "output" => 0.01,    "cached_input" => 0.0002,  "tier" => "standard" },
    # Google
    "gemini-2.0-flash"           => { "input" => 0.0001,  "output" => 0.0004,  "cached_input" => 0.000025, "tier" => "economy" },
    "gemini-1.5-pro"             => { "input" => 0.00125, "output" => 0.005,   "cached_input" => 0.000315, "tier" => "standard" },
    "gemini-1.5-flash"           => { "input" => 0.000075, "output" => 0.0003, "cached_input" => 0.00002,  "tier" => "economy" },
    # Groq (hosted models)
    "llama-3.3-70b-versatile"    => { "input" => 0.00059, "output" => 0.00079, "cached_input" => 0.00029, "tier" => "standard" },
    "llama-3.1-8b-instant"       => { "input" => 0.00005, "output" => 0.00008, "cached_input" => 0.000025, "tier" => "economy" },
    "mixtral-8x7b-32768"         => { "input" => 0.00024, "output" => 0.00024, "cached_input" => 0.00012, "tier" => "economy" },
    # Mistral
    "mistral-large"              => { "input" => 0.002,   "output" => 0.006,   "cached_input" => 0.001,   "tier" => "standard" },
    "mistral-small"              => { "input" => 0.0002,  "output" => 0.0006,  "cached_input" => 0.0001,  "tier" => "economy" },
    "codestral"                  => { "input" => 0.0003,  "output" => 0.0009,  "cached_input" => 0.00015, "tier" => "economy" },
    # Cohere
    "command-r-plus"             => { "input" => 0.0025,  "output" => 0.01,    "cached_input" => 0.00125, "tier" => "standard" },
    "command-r"                  => { "input" => 0.00015, "output" => 0.0006,  "cached_input" => 0.000075, "tier" => "economy" }
  }.freeze

  # Helper class to wrap HTTP responses with success? method
  class ResponseWrapper
    attr_reader :body, :code, :message

    def initialize(response, error: nil)
      if response
        @body = response.body
        @code = response.code.to_i
        @message = response.message
        @success = response.is_a?(Net::HTTPSuccess)
      else
        @body = ""
        @code = 0
        @message = error || "Connection failed"
        @success = false
      end
    end

    def success?
      @success
    end
  end

  # Instance-level initialization for provider testing
  def initialize(credential_or_provider)
    if credential_or_provider.is_a?(Ai::Provider)
      @provider = credential_or_provider
      @credential = credential_or_provider.provider_credentials.active.first
    else
      @credential = credential_or_provider
      @provider = credential_or_provider.provider
    end
    @test_config = {
      timeout: 10,
      max_retries: 3,
      test_message: "Hello, this is a test message."
    }
    @test_results = {}
    @health_check_results = []
  end

  # Instance method for simplified provider-level connection test
  def test_provider_connection
    result = test_connection
    {
      success: result[:success],
      message: result[:success] ? "Connection successful" : (result[:error_details] || result[:error_type]),
      response_time_ms: result[:response_time_ms]
    }
  end
end
