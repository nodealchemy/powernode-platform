# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Proxies LLM calls from the server to the worker process.
# The server NEVER calls AI providers directly -- all LLM calls
# go through the worker which owns the provider credentials and HTTP clients.
#
# Drop-in replacement for Ai::Llm::Client -- same public API (complete,
# stream, complete_with_tools, complete_structured) returning Ai::Llm::Response.
#
# Usage:
#   # From provider + credential (most common -- mirrors Ai::Llm::Client.new)
#   client = WorkerLlmClient.new(provider: provider, credential: credential)
#   response = client.complete(messages: msgs, model: "gpt-4.1")
#
#   # From agent_id (worker resolves provider config via internal API)
#   client = WorkerLlmClient.new(agent_id: agent.id)
#
#   # Factory: from account (finds best credential)
#   client = WorkerLlmClient.for_account(account, provider_type: "anthropic")
#
class WorkerLlmClient
  class WorkerLlmError < StandardError; end

  LLM_TIMEOUT = 120 # seconds -- LLM calls can be slow
  OPEN_TIMEOUT = 10  # seconds

  # Per-million-token cost rates (USD) for cost estimation.
  # More specific prefixes must come before less specific ones (prefix matching).
  COST_RATES = {
    "claude-opus" => { input: 15.00, output: 75.00 },
    "claude-sonnet" => { input: 3.00, output: 15.00 },
    "claude-haiku" => { input: 0.80, output: 4.00 },
    "gpt-4.1-nano" => { input: 0.10, output: 0.40 },
    "gpt-4.1-mini" => { input: 0.40, output: 1.60 },
    "gpt-4.1" => { input: 2.00, output: 8.00 },
    "gpt-4o-mini" => { input: 0.15, output: 0.60 },
    "gpt-4o" => { input: 2.50, output: 10.00 },
    "o3-mini" => { input: 1.10, output: 4.40 },
    "o4-mini" => { input: 1.10, output: 4.40 },
    "o3" => { input: 2.00, output: 8.00 }
  }.freeze

  attr_reader :provider, :credential

  # Build a client for a specific provider + credential pair, or from an agent_id.
  #
  # When provider + credential are given, the worker receives them directly and
  # skips the provider_config lookup (no agent_id round-trip needed).
  #
  # When only agent_id is given, the worker resolves provider config via
  # POST /api/v1/internal/ai/provider_config.
  def initialize(provider: nil, credential: nil, agent_id: nil, budget: nil)
    @provider = provider
    @credential = credential
    @agent_id = agent_id
    @budget = budget
    @worker_url = Rails.application.config.worker_url
  end

  # Factory: build from provider + credential (explicit)
  def self.for_provider(provider:, credential:)
    new(provider: provider, credential: credential)
  end

  # Factory: build from account (finds best credential, mirrors Ai::Llm::Client.for_account)
  def self.for_account(account, provider_type: nil)
    scope = account.ai_provider_credentials.active.includes(:provider)
    scope = scope.joins(:provider).where(ai_providers: { provider_type: provider_type }) if provider_type
    credential = scope.first
    return nil unless credential

    new(provider: credential.provider, credential: credential)
  end

  # =========================================================================
  # MAIN API (mirrors Ai::Llm::Client)
  # =========================================================================

  # Standard completion
  def complete(messages:, model:, **opts)
    result = call_worker("/api/v1/llm/complete", build_payload(
      messages: messages,
      model: model,
      **opts.slice(:max_tokens, :temperature, :system_prompt, :top_p, :stop)
    ))
    response = build_response(result)
    track_llm_usage!(response, model)
    response
  end

  # Streaming completion -- worker collects full stream, returns final result.
  # For real-time streaming to end users, use Ai::StreamingService which
  # dispatches to worker jobs and relays via ActionCable.
  def stream(messages:, model:, **opts, &block)
    result = call_worker("/api/v1/llm/stream", build_payload(
      messages: messages,
      model: model,
      **opts.slice(:max_tokens, :temperature, :system_prompt, :top_p, :stop)
    ))
    response = build_response(result)
    track_llm_usage!(response, model)

    # Simulate stream events for callers that expect a block
    if block_given?
      stream_id = SecureRandom.uuid
      yield Ai::Llm::Chunk.new(type: :stream_start, stream_id: stream_id, timestamp: Time.current.iso8601)
      if response.content.present?
        yield Ai::Llm::Chunk.new(type: :content_delta, content: response.content, stream_id: stream_id, timestamp: Time.current.iso8601)
      end
      yield Ai::Llm::Chunk.new(type: :stream_end, done: true, usage: response.usage, stream_id: stream_id, timestamp: Time.current.iso8601)
    end

    response
  end

  # Tool-enabled completion
  def complete_with_tools(messages:, tools:, model:, **opts)
    result = call_worker("/api/v1/llm/complete_with_tools", build_payload(
      messages: messages,
      tools: tools,
      model: model,
      **opts.slice(:max_tokens, :temperature, :tool_choice, :system_prompt)
    ))
    response = build_response(result)
    track_llm_usage!(response, model)
    response
  end

  # Structured output (JSON schema enforced)
  def complete_structured(messages:, schema:, model:, **opts)
    result = call_worker("/api/v1/llm/complete_structured", build_payload(
      messages: messages,
      schema: schema,
      model: model,
      **opts.slice(:max_tokens, :temperature)
    ))
    response = build_response(result)
    track_llm_usage!(response, model)
    response
  end

  # Full agentic tool loop -- LLM calls happen on the worker,
  # tool definitions and dispatch go through the server internal API.
  def execute_tool_loop(messages:, model:, **opts)
    call_worker("/api/v1/llm/execute_tool_loop", build_payload(
      messages: messages,
      model: model,
      **opts.slice(:max_iterations, :max_tokens, :temperature)
    ))
  end

  # =========================================================================
  # COMPATIBILITY DELEGATES
  # =========================================================================

  def provider_name
    @provider&.name || "unknown"
  end

  def provider_type
    @provider&.provider_type || "unknown"
  end

  private

  # Build the worker request payload.
  #
  # When we have provider + credential objects, we pass credential_id and
  # provider info directly so the worker can skip the agent-based provider_config
  # lookup. When we only have agent_id, we pass that and let the worker resolve.
  def build_payload(**params)
    payload = {}

    if @agent_id.present?
      payload[:agent_id] = @agent_id
    elsif @credential
      # Pass credential + provider info directly.
      # The worker uses credential_id to resolve the decrypted API key,
      # and provider_type/base_url to build the right client.
      payload[:credential_id] = @credential.id
      payload[:provider_type] = @provider&.provider_type
      payload[:provider_base_url] = @provider&.api_base_url
      payload[:provider_name] = @provider&.name
    end

    payload.merge(params.compact)
  end

  def call_worker(path, payload)
    uri = URI("#{@worker_url}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.read_timeout = LLM_TIMEOUT
    http.open_timeout = OPEN_TIMEOUT

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request["Accept"] = "application/json"
    request["Authorization"] = "Bearer #{WorkerJobService.system_worker_jwt}"
    request.body = payload.to_json

    response = http.request(request)
    parsed = JSON.parse(response.body)

    case response.code.to_i
    when 200..299
      parsed
    else
      error_msg = parsed["error"] || "Worker LLM call failed (HTTP #{response.code})"
      Rails.logger.error "[WorkerLlmClient] #{path} failed (#{response.code}): #{error_msg}"
      raise WorkerLlmError, error_msg
    end
  rescue Net::ReadTimeout, Net::OpenTimeout => e
    Rails.logger.error "[WorkerLlmClient] Timeout on #{path}: #{e.message}"
    raise WorkerLlmError, "Worker LLM timeout: #{e.message}"
  rescue Errno::ECONNREFUSED, SocketError => e
    Rails.logger.error "[WorkerLlmClient] Connection error on #{path}: #{e.message}"
    raise WorkerLlmError, "Worker unavailable: #{e.message}"
  rescue JSON::ParserError => e
    Rails.logger.error "[WorkerLlmClient] Invalid JSON response from #{path}: #{e.message}"
    raise WorkerLlmError, "Invalid response from worker"
  end

  # Build an Ai::Llm::Response from the worker's JSON response.
  # The worker returns format: { "content", "usage", "finish_reason", "model", ... }
  # which matches LlmProxyClient#format_response output.
  def build_response(result)
    # Worker wraps in { "data": ... } for success responses
    data = result.is_a?(Hash) && result.key?("data") ? result["data"] : result
    data = {} unless data.is_a?(Hash)

    Ai::Llm::Response.new(
      content: data["content"],
      tool_calls: normalize_tool_calls(data["tool_calls"]),
      finish_reason: data["finish_reason"] || "stop",
      model: data["model"],
      usage: symbolize_usage(data["usage"]),
      thinking_content: data["thinking_content"],
      cost: data["cost"],
      provider: provider_name
    )
  end

  def normalize_tool_calls(raw)
    return [] unless raw.is_a?(Array)

    raw.map { |tc| tc.is_a?(Hash) ? tc.deep_symbolize_keys : tc }
  end

  def symbolize_usage(raw)
    return {} unless raw.is_a?(Hash)

    raw.deep_symbolize_keys
  end

  # Debit the agent's budget based on token usage from the response.
  # Uses ceil rounding (minimum 1 cent) since spent_cents is an integer column.
  def track_llm_usage!(response, model)
    return unless @agent_id
    return unless response.total_tokens > 0 && response.finish_reason != "error"

    cost_cents = estimate_cost_cents(model, response.prompt_tokens, response.completion_tokens)
    cost_cents = [cost_cents, 1].max

    budget = resolve_agent_budget
    return unless budget

    budget.debit!(cost_cents, metadata: {
      provider: response.provider,
      model: model,
      prompt_tokens: response.prompt_tokens,
      completion_tokens: response.completion_tokens,
      total_tokens: response.total_tokens,
      estimated_cost_usd: (cost_cents / 100.0).round(4),
      source: "worker_llm_client"
    })
  rescue StandardError => e
    Rails.logger.warn("[WorkerLlmClient] Budget tracking failed: #{e.class}: #{e.message}")
  end

  def estimate_cost_cents(model, input_tokens, output_tokens)
    rates = COST_RATES.find { |prefix, _| model.to_s.start_with?(prefix) }&.last
    rates ||= { input: 1.00, output: 4.00 }

    cost_usd = (input_tokens * rates[:input] / 1_000_000.0) +
               (output_tokens * rates[:output] / 1_000_000.0)
    (cost_usd * 100).ceil
  end

  def resolve_agent_budget
    @_agent_budget ||= @budget || Ai::AgentBudget.active
                                                   .where(agent_id: @agent_id)
                                                   .order(created_at: :desc)
                                                   .first
  end
end
