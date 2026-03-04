# frozen_string_literal: true

module Ai
  module LlmCallable
    extend ActiveSupport::Concern

    private

    # Proxy an LLM completion through the worker process.
    #
    # Replaces the non-existent Ai::LlmService with a WorkerLlmClient call,
    # returning the same hash format the callers expect:
    #   { content: "...", cost_usd: 0.001 }
    #
    # @param agent [Ai::Agent] Agent context (required by worker for provider resolution)
    # @param prompt [String] The prompt text
    # @param max_tokens [Integer] Max tokens for completion
    # @param temperature [Float] Sampling temperature
    # @return [Hash, nil] { content: "...", cost_usd: 0.001 } or nil on failure
    def call_llm(agent:, prompt:, max_tokens: 500, temperature: 0.3)
      unless agent
        Rails.logger.warn "[#{self.class.name}] call_llm requires an agent context"
        return nil
      end

      client = WorkerLlmClient.new(agent_id: agent.id)
      model = resolve_model(agent)

      response = client.complete(
        messages: [{ role: "user", content: prompt }],
        model: model,
        max_tokens: max_tokens,
        temperature: temperature
      )

      { content: response.content, cost_usd: response.cost.to_f }
    rescue WorkerLlmClient::WorkerLlmError => e
      Rails.logger.warn "[#{self.class.name}] LLM call failed: #{e.message}"
      nil
    end

    # Resolve the model to use from the agent's provider config.
    # Falls back to the provider's cheapest chat model if agent config is empty.
    def resolve_model(agent)
      # Agent's MCP metadata may specify a model
      configured = agent.mcp_metadata&.dig("model_config", "model")
      return configured if configured.present?

      # Fall back to the provider's cheapest chat-capable model
      provider = agent.provider
      return "gpt-4.1-mini" unless provider

      models = provider.supported_models || []
      chat_models = models.select { |m| m["capabilities"]&.include?("text_generation") }
      mini = chat_models.find { |m| m["id"].to_s.include?("mini") }
      (mini || chat_models.first || models.first)&.dig("id") || "gpt-4.1-mini"
    end
  end
end
