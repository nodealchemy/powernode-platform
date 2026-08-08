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

  # `account:` is the account USING the agent. It matters for GLOBAL agents
  # (account_id nil), which are shared platform-wide and adopted per-account via
  # Ai::Agent#using_account — exactly what AgentBackedService#resolve_service_agent
  # returns. Without it, create_execution_record built the row with
  # `account: @agent.account` => nil, create! failed "Account must exist", and
  # the rescue below swallowed it: no execution, no cost, no tokens, no budget
  # debit, while the LLM call itself succeeded. Every global agent reaching this
  # decorator was silently untracked.
  def initialize(inner_client:, agent:, execution_context_type: nil, account: nil)
    @inner  = inner_client
    @agent  = agent
    @account = account
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
    routing_decision_id = opts.delete(:routing_decision_id)
    execution = create_execution_record(method, messages, opts)
    link_routing_decision(execution, routing_decision_id)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    response = @inner.public_send(method, messages: messages, **opts)

    record_success(execution, response, started_at)
    response
  rescue => e
    record_failure(execution, e, started_at)
    raise
  end

  # inc: link a tier-routing decision (persisted before this call, since it has
  # no AgentExecution of its own yet — see AgentBackedService#resolve_task_tier)
  # to the execution this call just created, so
  # Ai::AgentExecution#record_routing_decision_outcome can feed the outcome back
  # onto it once this execution completes/fails.
  def link_routing_decision(execution, routing_decision_id)
    return unless execution && routing_decision_id

    Ai::RoutingDecision.where(id: routing_decision_id, outcome: nil)
                        .update_all(agent_execution_id: execution.id)
  rescue => e
    Rails.logger.warn "[TrackedWorkerLlmClient] Failed to link routing decision #{routing_decision_id}: #{e.message}"
  end

  def create_execution_record(method, messages, opts)
    Ai::AgentExecution.create!(
      agent: @agent,
      # Explicit using-account first; an account-owned agent still falls back to
      # its own. nil for both is a genuinely unattributable call and will fail
      # validation loudly in the log rather than pretending it recorded.
      account: @account || @agent.account,
      user: resolve_user,
      provider: @agent.resolved_provider || @agent.provider,
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

    # Calculate accurate cost using the canonical service instead of
    # relying on response.cost which may be 0.0 from the worker
    cost = Ai::CostCalculationService.calculate(
      model_id: response.model.to_s,
      prompt_tokens: response.prompt_tokens,
      completion_tokens: response.completion_tokens,
      cached_tokens: response.cached_tokens
    )

    execution.update!(
      status: "completed",
      completed_at: Time.current,
      duration_ms: duration,
      output_data: {
        content: response.content&.truncate(OUTPUT_TRUNCATE_LENGTH),
        prompt_tokens: response.prompt_tokens,
        completion_tokens: response.completion_tokens,
        cached_tokens: response.cached_tokens
      },
      tokens_used: response.total_tokens,
      cost_usd: cost,
      performance_metrics: {
        prompt_tokens: response.prompt_tokens,
        completion_tokens: response.completion_tokens,
        cached_tokens: response.cached_tokens,
        model: response.model,
        provider: response.provider,
        # Served-by attribution for the model-performance signal: on a Fable→X
        # fallback the SUCCESS belongs to X, not the configured Fable model. On a
        # terminal refusal, `refused` tells record_model_performance to skip
        # (WorkerLlmClient already recorded the refused-model failure).
        served_by: (response.respond_to?(:served_by) ? response.served_by : nil),
        refused: (response.respond_to?(:refused?) ? response.refused? : false)
      }.compact
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
