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
# Model names are NEVER hardcoded — resolve from the agent's model_config or
# the provider's available models (Ai::AgentModelSelector picks one for new
# agents). Prefer routing work through an Ai::Agent over direct calls.
#
# Usage:
#   # From provider + credential (most common -- mirrors Ai::Llm::Client.new)
#   client = WorkerLlmClient.new(provider: provider, credential: credential)
#   response = client.complete(messages: msgs, model: agent_model_config["model"])
#
#   # From agent_id (worker resolves provider config via internal API)
#   client = WorkerLlmClient.new(agent_id: agent.id)
#
#   # Factory: from account (finds best credential)
#   client = WorkerLlmClient.for_account(account, provider_type: "anthropic")
#
class WorkerLlmClient
  class WorkerLlmError < StandardError; end

  # A single worker call can now run up to THREE sequential provider attempts
  # (original → reframe → non-Fable fallback) inside the refusal handler, and
  # Fable turns are themselves minutes-long — so the server→worker read timeout
  # is generous enough to cover the full adapt→fallback path without aborting
  # mid-recovery. (The worker's own per-attempt provider timeout is separate.)
  LLM_TIMEOUT = 600 # seconds -- LLM calls can be slow; refusal recovery is up to 3 attempts
  OPEN_TIMEOUT = 10  # seconds

  attr_reader :provider, :credential

  # Build a client for a specific provider + credential pair, or from an agent_id.
  #
  # When provider + credential are given, the worker receives them directly and
  # skips the provider_config lookup (no agent_id round-trip needed).
  #
  # When only agent_id is given, the worker resolves provider config via
  # POST /api/v1/internal/ai/provider_config.
  def initialize(provider: nil, credential: nil, agent_id: nil, budget: nil, skip_budget_tracking: false)
    @provider = provider
    @credential = credential
    @agent_id = agent_id
    @budget = budget
    @skip_budget_tracking = skip_budget_tracking
    @transport = WorkerTransport.new(open_timeout: OPEN_TIMEOUT, read_timeout: LLM_TIMEOUT)
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
      **opts.slice(:max_tokens, :temperature, :system_prompt, :top_p, :stop, :effort)
    ))
    response = build_response(result)
    track_llm_usage!(response, model)
    record_refusal!(response, model)
    response
  end

  # Streaming completion -- worker collects full stream, returns final result.
  # For real-time streaming to end users, use Ai::StreamingService which
  # dispatches to worker jobs and relays via ActionCable.
  def stream(messages:, model:, **opts, &block)
    result = call_worker("/api/v1/llm/stream", build_payload(
      messages: messages,
      model: model,
      **opts.slice(:max_tokens, :temperature, :system_prompt, :top_p, :stop, :effort)
    ))
    response = build_response(result)
    track_llm_usage!(response, model)
    record_refusal!(response, model)

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
      **opts.slice(:max_tokens, :temperature, :tool_choice, :system_prompt, :effort)
    ))
    response = build_response(result)
    track_llm_usage!(response, model)
    record_refusal!(response, model)
    response
  end

  # Structured output (JSON schema enforced)
  def complete_structured(messages:, schema:, model:, **opts)
    result = call_worker("/api/v1/llm/complete_structured", build_payload(
      messages: messages,
      schema: schema,
      model: model,
      **opts.slice(:max_tokens, :temperature, :effort)
    ))
    response = build_response(result)
    track_llm_usage!(response, model)
    record_refusal!(response, model)
    response
  end

  # Full agentic tool loop -- LLM calls happen on the worker,
  # tool definitions and dispatch go through the server internal API.
  def execute_tool_loop(messages:, model:, **opts)
    result = call_worker("/api/v1/llm/execute_tool_loop", build_payload(
      messages: messages,
      model: model,
      **opts.slice(:max_iterations, :max_tokens, :temperature, :effort)
    ))

    # Build response from accumulated usage so budget tracking works
    data = result.is_a?(Hash) && result.key?("data") ? result["data"] : result
    data = {} unless data.is_a?(Hash)
    usage = data["usage"] || {}

    response = Ai::Llm::Response.new(
      content: data["content"],
      finish_reason: data["finish_reason"] || "stop",
      model: model,
      usage: symbolize_usage(usage),
      cost: data["cost"],
      provider: provider_name,
      refusal: data["refusal"],
      served_by: data["served_by"],
      refusal_recovery: data["refusal_recovery"]
    )
    track_llm_usage!(response, model)
    record_refusal!(response, model)

    result
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

  # Shared Net::HTTP + JWT plumbing lives in WorkerTransport; this maps its
  # typed errors onto WorkerLlmError semantics.
  def call_worker(path, payload)
    @transport.post(path, payload)
  rescue WorkerTransport::HttpError => e
    error_msg = (e.parsed.is_a?(Hash) && e.parsed["error"]) || "Worker LLM call failed (HTTP #{e.status})"
    Rails.logger.error "[WorkerLlmClient] #{path} failed (#{e.status}): #{error_msg}"
    raise WorkerLlmError, error_msg
  rescue WorkerTransport::TimeoutError => e
    Rails.logger.error "[WorkerLlmClient] Timeout on #{path}: #{e.message}"
    raise WorkerLlmError, "Worker LLM timeout: #{e.message}"
  rescue WorkerTransport::ConnectionError => e
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
      provider: provider_name,
      # Refusal metadata threaded back from the worker's refusal handler.
      refusal: data["refusal"],
      served_by: data["served_by"],
      refusal_recovery: data["refusal_recovery"]
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
  # Uses CostCalculationService for accurate pricing with cached token discounting.
  def track_llm_usage!(response, model)
    return if @skip_budget_tracking
    return unless @agent_id
    return unless response.total_tokens > 0 && response.finish_reason != "error"

    cost_cents = Ai::CostCalculationService.calculate_cents(
      model_id: model.to_s,
      prompt_tokens: response.prompt_tokens,
      completion_tokens: response.completion_tokens,
      cached_tokens: response.cached_tokens
    )
    return if cost_cents <= 0

    budget = resolve_agent_budget
    return unless budget

    budget.debit!(cost_cents, metadata: {
      provider: response.provider,
      model: model,
      prompt_tokens: response.prompt_tokens,
      completion_tokens: response.completion_tokens,
      cached_tokens: response.cached_tokens,
      total_tokens: response.total_tokens,
      estimated_cost_usd: (cost_cents / 100.0).round(6),
      source: "worker_llm_client"
    })
  rescue StandardError => e
    Rails.logger.warn("[WorkerLlmClient] Budget tracking failed: #{e.class}: #{e.message}")
  end

  def resolve_agent_budget
    @_agent_budget ||= @budget || Ai::AgentBudget.active
                                                   .where(agent_id: @agent_id)
                                                   .order(created_at: :desc)
                                                   .first
  end

  # LEARN step: whenever the worker reports a refusal (recovered or terminal),
  # log it LOUDLY, append an Ai::ModelRefusalEvent, record a FAILURE for the
  # refused (model, agent_type) so its AgentModelSelector empirical score drops,
  # and let the promotion service pre-route past-threshold combos away from Fable.
  # Universal: every agent-scoped WorkerLlmClient call site flows through here
  # (including the TrackedWorkerLlmClient wrapper, which delegates to this inner
  # client). Best-effort — a learning-log write must never break the LLM call.
  def record_refusal!(response, model)
    recovery = response.respond_to?(:refusal_recovery) ? response.refusal_recovery : nil
    refusal  = response.respond_to?(:refusal) ? response.refusal : nil
    return unless recovery.present? || refusal.present?

    category  = dig_meta(recovery, "category") || dig_meta(refusal, "category")
    phase     = dig_meta(recovery, "phase") || dig_meta(refusal, "phase") || "pre_output"
    served_by = dig_meta(recovery, "served_by")
    reframed  = recovery ? !!dig_meta(recovery, "reframed") : false
    fell_back = recovery ? !!dig_meta(recovery, "fell_back") : false
    ctx = refusal_recording_context

    # LOUD, attributed — fires even when we cannot attribute/record to a row.
    Rails.logger.warn(
      "[Refusal] model=#{model} agent_type=#{ctx[:agent_type] || 'unknown'} " \
      "category=#{category || 'null'} phase=#{phase} reframed=#{reframed} " \
      "fell_back=#{fell_back} served_by=#{served_by || 'none'}"
    )

    return if ctx[:account_id].blank? || ctx[:provider_id].blank? || ctx[:agent_type].blank?

    event = Ai::ModelRefusalEvent.record!(
      account_id: ctx[:account_id], provider_id: ctx[:provider_id],
      model: model, agent_type: ctx[:agent_type],
      phase: phase, category: category,
      reframed: reframed, fell_back: fell_back,
      served_by_model: served_by,
      explanation: dig_meta(refusal, "explanation")
    )

    # A refusal is a FAILURE for the refused (model, agent_type).
    Ai::AgentModelPerformance.record!(
      account_id: ctx[:account_id], provider_id: ctx[:provider_id],
      model: model, agent_type: ctx[:agent_type], success: false
    )

    if event
      # Only pre-route toward a model we actually FELL BACK to. On a reframe-success
      # served_by is the (refusing) Fable model itself — pre-routing to it would send
      # traffic straight back to the refuser and could clobber a correct Opus rule.
      promote_target = fell_back ? served_by : nil
      Ai::ModelRefusalPromotionService.new(account_id: ctx[:account_id]).maybe_promote(
        model: model, agent_type: ctx[:agent_type], category: category, fallback_model: promote_target
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[WorkerLlmClient] refusal recording failed: #{e.class}: #{e.message}")
  end

  def dig_meta(hash, key)
    return nil unless hash.is_a?(Hash)

    hash[key] || hash[key.to_sym]
  end

  # Resolve (account, provider, agent_type) for the refused call. The provider is
  # the one that actually served (resolved_provider), so the failure lands on the
  # same (account, provider, model, agent_type) tuple AgentModelSelector scores.
  def refusal_recording_context
    @_refusal_ctx ||= if @agent_id.present?
                        agent = Ai::Agent.find_by(id: @agent_id)
                        if agent
                          prov = (agent.resolved_provider rescue nil) || agent.provider
                          { account_id: agent.account_id, provider_id: prov&.id, agent_type: agent.agent_type }
                        else
                          {}
                        end
                      elsif @provider
                        { account_id: @provider.account_id, provider_id: @provider.id, agent_type: nil }
                      else
                        {}
                      end
  end
end
