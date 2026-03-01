# frozen_string_literal: true

# Decorator that wraps WorkerLlmClient to automatically create
# Ai::AgentExecution records for every LLM call.
#
# This gives agent-backed services (PRD generator, RAG reranker, etc.)
# execution history, token tracking, cost propagation, and trust scoring
# without requiring any changes to consumer code.
#
# Tracking is best-effort: if record creation/update fails, the LLM call
# still proceeds normally and the error is logged.
#
# Usage (via AgentBackedService#build_agent_client):
#   client = build_agent_client(agent)          # returns TrackedWorkerLlmClient
#   client = build_agent_client(agent, tracked: false)  # returns raw WorkerLlmClient
#
class TrackedWorkerLlmClient
  INPUT_TRUNCATE_LENGTH  = 2_000
  OUTPUT_TRUNCATE_LENGTH = 10_000

  TRACKED_METHODS = %i[complete complete_structured complete_with_tools].freeze

  def initialize(inner_client:, agent:, execution_context_type: nil)
    @inner  = inner_client
    @agent  = agent
    @execution_context_type = execution_context_type
  end

  # --- Tracked LLM methods ---

  def complete(messages:, **opts)
    tracked_call(:complete, messages, **opts)
  end

  def complete_structured(messages:, **opts)
    tracked_call(:complete_structured, messages, **opts)
  end

  def complete_with_tools(messages:, **opts)
    tracked_call(:complete_with_tools, messages, **opts)
  end

  # --- Delegate everything else to inner client ---

  def respond_to_missing?(method_name, include_private = false)
    @inner.respond_to?(method_name, include_private) || super
  end

  def method_missing(method_name, ...)
    if @inner.respond_to?(method_name)
      @inner.public_send(method_name, ...)
    else
      super
    end
  end

  private

  def tracked_call(method, messages, **opts)
    execution = create_execution_record(method, messages, opts)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    response = @inner.public_send(method, messages: messages, **opts)

    record_success(execution, response, started_at)
    response
  rescue => e
    record_failure(execution, e, started_at)
    raise
  end

  def create_execution_record(method, messages, opts)
    Ai::AgentExecution.create!(
      agent: @agent,
      account: @agent.account,
      user: resolve_user,
      provider: @agent.provider,
      status: "running",
      started_at: Time.current,
      input_parameters: build_input_params(method, messages, opts),
      execution_context: build_execution_context(method)
    )
  rescue => e
    Rails.logger.warn "[TrackedWorkerLlmClient] Failed to create execution record: #{e.message}"
    nil
  end

  def record_success(execution, response, started_at)
    return unless execution

    duration = duration_ms(started_at)

    execution.update!(
      status: "completed",
      completed_at: Time.current,
      duration_ms: duration,
      output_data: { content: response.content&.truncate(OUTPUT_TRUNCATE_LENGTH) },
      tokens_used: response.total_tokens,
      cost_usd: response.cost || 0.0,
      performance_metrics: {
        prompt_tokens: response.prompt_tokens,
        completion_tokens: response.completion_tokens,
        cached_tokens: response.cached_tokens,
        model: response.model,
        provider: response.provider
      }
    )
  rescue => e
    Rails.logger.warn "[TrackedWorkerLlmClient] Failed to update execution #{execution.id}: #{e.message}"
  end

  def record_failure(execution, error, started_at)
    return unless execution

    execution.update!(
      status: "failed",
      completed_at: Time.current,
      duration_ms: started_at ? duration_ms(started_at) : nil,
      error_message: error.message&.truncate(1_000)
    )
  rescue => e
    Rails.logger.warn "[TrackedWorkerLlmClient] Failed to record failure for execution #{execution.id}: #{e.message}"
  end

  def resolve_user
    @agent.creator
  end

  def build_input_params(method, messages, opts)
    {
      method: method.to_s,
      message_count: messages.size,
      messages: truncated_messages(messages),
      model: opts[:model],
      temperature: opts[:temperature],
      max_tokens: opts[:max_tokens]
    }.compact
  end

  def build_execution_context(method)
    {
      context_type: @execution_context_type,
      method: method.to_s,
      tracked: true
    }.compact
  end

  def truncated_messages(messages)
    messages.map do |msg|
      m = msg.is_a?(Hash) ? msg : msg.to_h
      content = m[:content] || m["content"]
      {
        role: m[:role] || m["role"],
        content: content.is_a?(String) ? content.truncate(INPUT_TRUNCATE_LENGTH) : "(non-text)"
      }
    end
  end

  def duration_ms(started_at)
    return nil unless started_at

    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end
end
