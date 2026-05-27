# frozen_string_literal: true

require_relative '../../services/llm_proxy_client'
require_relative '../../services/action_cable_client'

# Provides worker jobs with access to server-side LLM proxy and execution context.
# Supports WebSocket transport for tool dispatch with automatic HTTP fallback.
module AiLlmProxyConcern
  extend ActiveSupport::Concern

  private

  # Standard HTTP-only LLM proxy client
  def llm_proxy
    @llm_proxy ||= ::LlmProxyClient.new(method(:backend_api_post), method(:backend_api_get))
  end

  # Returns a WebSocket-enabled LLM proxy, or nil if connection fails.
  # Memoized per job execution; call disconnect_tool_dispatch_ws to clean up.
  def llm_proxy_with_websocket
    return @_ws_proxy if @_ws_attempted
    @_ws_attempted = true

    @_ws_client = connect_tool_dispatch_ws
    @_ws_proxy = if @_ws_client
      ::LlmProxyClient.new(
        method(:backend_api_post), method(:backend_api_get), ws_client: @_ws_client
      )
    end
  end

  # Establish a WebSocket connection to the server's ActionCable endpoint.
  # mTLS at the TLS handshake — WorkerCertManager + the websocket-client-simple
  # monkey patch present the worker's client cert. ApplicationCable::Connection
  # resolves the worker from the cert CN.
  #
  # URL priority: explicit WORKER_CABLE_URL env (wss://host:4443/cable in prod),
  # else BACKEND_API_URL with /cable appended (works for dev plaintext + tests).
  # Returns an ActionCableClient or nil on failure (caller falls back to HTTP).
  def connect_tool_dispatch_ws
    ws_url = ENV.fetch("WORKER_CABLE_URL") do
      base_url = ENV.fetch("BACKEND_API_URL", "http://localhost:3000")
      base_url.sub(/^http/, "ws") + "/cable"
    end

    client = ::ActionCableClient.new(ws_url)
    client.connect
    log_info("[LlmProxy] WebSocket connection established to #{ws_url}")
    client
  rescue StandardError => e
    log_info("[LlmProxy] WebSocket unavailable, using HTTP: #{e.message}")
    nil
  end

  # Clean up WebSocket connection after job execution.
  def disconnect_tool_dispatch_ws
    @_ws_client&.disconnect
  rescue StandardError => e
    log_info("[LlmProxy] WebSocket disconnect error (non-fatal): #{e.message}") rescue nil
  ensure
    @_ws_client = nil
    @_ws_proxy = nil
    @_ws_attempted = nil
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
