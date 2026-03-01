# frozen_string_literal: true

require_relative '../../services/llm_proxy_client'

# Provides worker jobs with access to server-side LLM proxy and execution context.
# Replaces AiProviderCallsConcern, AiGenericProviderConcern, and AiPromptBuildingConcern
# by delegating all LLM calls through the server's internal API.
module AiLlmProxyConcern
  extend ActiveSupport::Concern

  private

  # Memoized LLM proxy client backed by the worker's API client
  def llm_proxy
    @llm_proxy ||= ::LlmProxyClient.new(method(:backend_api_post))
  end

  # Fetch a memory-enriched execution context from the server.
  # Returns: { execution_context:, system_prompt:, model:, max_tokens:, temperature: }
  def fetch_execution_context(agent_id, input_params = {})
    response = backend_api_post("/api/v1/internal/ai/execution_contexts", {
      agent_id: agent_id,
      input: input_params[:input] || input_params["input"],
      context: input_params[:context] || input_params["context"] || {},
      memory_token_budget: input_params[:memory_token_budget] || 4000
    })

    if response.is_a?(Hash) && response["success"]
      response["data"]
    else
      error_msg = response.is_a?(Hash) ? response["error"] : "Unknown error"
      raise "Failed to fetch execution context: #{error_msg}"
    end
  end
end
