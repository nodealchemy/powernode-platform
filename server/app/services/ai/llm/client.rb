# frozen_string_literal: true

module Ai
  module Llm
    # Unified LLM client — single entry point for all provider interactions
    #
    # Usage:
    #   client = Ai::Llm::Client.new(provider: provider, credential: credential)
    #   response = client.complete(messages: [{role: "user", content: "Hello"}], model: "gpt-4.1")
    #   response.content  # => "Hello! How can I help?"
    #   response.usage    # => {prompt_tokens: 5, completion_tokens: 10, ...}
    #
    #   # Streaming
    #   client.stream(messages: msgs, model: "claude-sonnet-4-5") do |chunk|
    #     print chunk.content if chunk.type == :content_delta
    #   end
    #
    #   # Tool calling
    #   tools = [{name: "get_weather", description: "...", parameters: {...}}]
    #   response = client.complete_with_tools(messages: msgs, tools: tools, model: "gpt-4.1")
    #   response.tool_calls  # => [{id: "...", name: "get_weather", arguments: {...}}]
    #
    #   # Structured output
    #   schema = {name: "person", schema: {type: "object", properties: {name: {type: "string"}}}}
    #   response = client.complete_structured(messages: msgs, schema: schema, model: "gpt-4.1")
    #
    class Client
      attr_reader :adapter, :provider, :credential

      # Initialize with provider record + credential
      # @param provider [Ai::Provider] the provider record
      # @param credential [Ai::ProviderCredential] the credential with API key
      def initialize(provider:, credential:)
        @provider = provider
        @credential = credential
        @adapter = AdapterFactory.build(provider: provider, credential: credential)
      end

      # Initialize directly from provider type (no DB records needed)
      # @param provider_type [String] "openai", "anthropic", "ollama"
      # @param api_key [String] API key
      # @param base_url [String] API base URL
      # @return [Ai::Llm::Client]
      def self.for_type(provider_type, api_key:, base_url: nil, provider_name: nil)
        adapter = AdapterFactory.build_for_type(
          provider_type, api_key: api_key, base_url: base_url, provider_name: provider_name
        )
        client = allocate
        client.instance_variable_set(:@adapter, adapter)
        client.instance_variable_set(:@provider, nil)
        client.instance_variable_set(:@credential, nil)
        client
      end

      # Build client from an account — finds the best available credential
      # @param account [Account] the account
      # @param provider_type [String] optional provider type filter
      # @return [Ai::Llm::Client, nil]
      def self.for_account(account, provider_type: nil)
        scope = account.ai_provider_credentials.active.includes(:provider)
        scope = scope.joins(:provider).where(ai_providers: { provider_type: provider_type }) if provider_type

        credential = scope.first
        return nil unless credential

        new(provider: credential.provider, credential: credential)
      end

      # =========================================================================
      # MAIN API
      # =========================================================================

      # Standard completion
      # @param messages [Array<Hash>] [{role: "user", content: "..."}]
      # @param model [String] model ID
      # @param opts [Hash] max_tokens, temperature, system_prompt, etc.
      # @return [Ai::Llm::Response]
      def complete(messages:, model:, **opts)
        with_circuit_breaker(model) do
          response = adapter.complete(messages: messages, model: model, **opts)
          track_usage(response, model)
          response
        end
      end

      # Streaming completion
      # @param messages [Array<Hash>]
      # @param model [String]
      # @param opts [Hash]
      # @yield [Ai::Llm::Chunk] chunks as they arrive
      # @return [Ai::Llm::Response] final accumulated response
      def stream(messages:, model:, **opts, &block)
        with_circuit_breaker(model) do
          response = adapter.stream(messages: messages, model: model, **opts, &block)
          track_usage(response, model)
          response
        end
      end

      # Completion with tool calling
      # @param messages [Array<Hash>]
      # @param tools [Array<Hash>] [{name:, description:, parameters:}]
      # @param model [String]
      # @param opts [Hash]
      # @return [Ai::Llm::Response]
      def complete_with_tools(messages:, tools:, model:, **opts)
        with_circuit_breaker(model) do
          response = adapter.complete_with_tools(messages: messages, tools: tools, model: model, **opts)
          track_usage(response, model)
          response
        end
      end

      # Completion with structured JSON output
      # @param messages [Array<Hash>]
      # @param schema [Hash] {name:, schema:} — JSON Schema
      # @param model [String]
      # @param opts [Hash]
      # @return [Ai::Llm::Response]
      def complete_structured(messages:, schema:, model:, **opts)
        with_circuit_breaker(model) do
          response = adapter.complete_structured(messages: messages, schema: schema, model: model, **opts)
          track_usage(response, model)
          response
        end
      end

      # =========================================================================
      # UTILITIES
      # =========================================================================

      def provider_name
        adapter.provider_name
      end

      def provider_type
        provider&.provider_type || adapter.provider_name
      end

      private

      def with_circuit_breaker(model)
        service_name = "llm_#{provider_name}_#{model}".gsub(/[^a-zA-Z0-9_]/, "_")

        Ai::CircuitBreakerRegistry.protect(service_name: service_name) do
          yield
        end
      rescue CircuitBreakerCore::CircuitOpenError => e
        Rails.logger.error "[LLM] Circuit breaker open for #{service_name}: #{e.message}"
        Ai::Llm::Response.new(
          content: nil,
          provider: provider_name,
          finish_reason: "error",
          raw_response: { error: "Circuit breaker open", service: service_name }
        )
      end

      def track_usage(response, model)
        return unless response.success? && provider

        usage = response.usage
        return if usage[:total_tokens].zero?

        # Look up pricing
        pricing = Ai::ProviderManagementService.model_pricing_for(model)
        cost = estimate_cost(usage, pricing)
        response.instance_variable_set(:@cost, cost)

        # Record metric asynchronously
        record_usage_metric(model, usage, cost)
      rescue StandardError => e
        Rails.logger.warn "[LLM] Failed to track usage: #{e.message}"
      end

      def estimate_cost(usage, pricing)
        return 0.0 unless pricing

        prompt_cost = (usage[:prompt_tokens] / 1000.0) * (pricing["input"] || 0)
        completion_cost = (usage[:completion_tokens] / 1000.0) * (pricing["output"] || 0)
        cached_discount = if usage[:cached_tokens].positive? && pricing["cached_input"]
                            (usage[:cached_tokens] / 1000.0) * (pricing["input"].to_f - pricing["cached_input"].to_f)
                          else
                            0.0
                          end

        (prompt_cost + completion_cost - cached_discount).round(6)
      end

      def record_usage_metric(model, usage, cost)
        return unless provider

        Ai::ProviderMetric.create(
          ai_provider: provider,
          model_name: model,
          request_type: "chat_completion",
          tokens_used: usage[:total_tokens],
          prompt_tokens: usage[:prompt_tokens],
          completion_tokens: usage[:completion_tokens],
          cost_per_1k_tokens: cost > 0 ? (cost / (usage[:total_tokens] / 1000.0)).round(6) : 0,
          total_cost_usd: cost,
          success: true,
          recorded_at: Time.current
        )
      rescue StandardError => e
        Rails.logger.warn "[LLM] Failed to record metric: #{e.message}"
      end
    end
  end
end
