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
      request_llm(:complete, agent: agent, prompt: prompt, max_tokens: max_tokens, temperature: temperature)
    end

    # The same call with structured output: the API enforces `schema`
    # ({name:, schema:}), so `content` is that JSON, unparsed. Same return
    # shape and failure contract as #call_llm.
    def call_llm_structured(agent:, prompt:, schema:, max_tokens: 500, temperature: 0.3)
      request_llm(:complete_structured, agent: agent, prompt: prompt, max_tokens: max_tokens,
                                        temperature: temperature, schema: schema)
    end

    def request_llm(method, agent:, prompt:, max_tokens:, temperature:, **extra)
      unless agent
        Rails.logger.warn "[#{self.class.name}] #{method} requires an agent context"
        return nil
      end

      client = WorkerLlmClient.new(agent_id: agent.id)
      response = client.public_send(
        method,
        messages: [ { role: "user", content: prompt } ],
        model: resolve_model(agent),
        max_tokens: max_tokens,
        temperature: temperature,
        **extra
      )

      { content: response.content, cost_usd: response.cost.to_f }
    rescue WorkerLlmClient::WorkerLlmError => e
      Rails.logger.warn "[#{self.class.name}] LLM call failed: #{e.message}"
      nil
    end

    # #37: the agent owns model selection — its pinned model when set, else the
    # cost/capability-aware AgentModelSelector pick across ANY active, credentialed
    # provider, else the provider default. (Provider + credential for the worker
    # come from the agent's resolution triple via the internal provider_config
    # endpoint, so model and provider stay coherent.)
    def resolve_model(agent)
      agent.resolved_model
    end
  end
end
