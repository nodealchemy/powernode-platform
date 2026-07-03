# frozen_string_literal: true

# Mixin for services that delegate LLM calls to a dedicated Ai::Agent.
#
# Two resolution strategies:
#
# 1. **Skill-based discovery** (preferred) — describe what you need and
#    the platform finds the best agent via semantic matching:
#
#      agent = discover_service_agent("Score and rerank search results by relevance")
#
# 2. **Slug-based lookup** (fast path) — direct lookup by known slug,
#    used for infrastructure services or as fallback:
#
#      agent = resolve_service_agent("rag-reranker")
#
# Once resolved, build a client and call the worker:
#
#   client = build_agent_client(agent)
#   response = client.complete(messages: msgs, model: agent_model(agent), ...)
#
# The agent record owns the provider, credential resolution, model config,
# and system prompt — all editable via the API without code changes.
#
# Requires @account to be set on the including class.
module AgentBackedService
  extend ActiveSupport::Concern

  DISCOVERY_CACHE_TTL = 5.minutes
  DISCOVERY_MIN_SCORE = 0.35

  private

  # Discover the best agent for a task using semantic skill/tool discovery.
  #
  # Uses SemanticToolDiscoveryService to rank all active agents against
  # a natural-language task description. Falls back to slug-based lookup
  # when discovery is unavailable or returns no results.
  #
  # @param task_description [String] what the agent needs to do
  # @param fallback_slug [String] slug for direct lookup if discovery fails
  # @param min_score [Float] minimum relevance score (0.0–1.0)
  # @return [Ai::Agent, nil]
  def discover_service_agent(task_description, fallback_slug: nil, min_score: DISCOVERY_MIN_SCORE)
    account = service_account
    return resolve_service_agent(fallback_slug) if account.nil? && fallback_slug

    agent = discover_agent_by_task(task_description, account, min_score)
    return agent if agent

    # Fallback to slug if discovery returned nothing
    resolve_service_agent(fallback_slug) if fallback_slug
  rescue StandardError => e
    Rails.logger.warn "[AgentBackedService] Discovery failed (#{e.message}), falling back to slug: #{fallback_slug}"
    fallback_slug ? resolve_service_agent(fallback_slug) : nil
  end

  # Look up a dedicated utility agent by slug (preferred) or name (fallback).
  # Returns nil if no matching agent exists.
  def resolve_service_agent(slug, fallback_name: nil)
    # for_account = the account's own agents + GLOBAL platform agents
    # (override-aware: an account copy wins over the global default). A global
    # agent has no providers of its own, so #using_account makes ALL of its
    # provider characteristics derive from THIS account's configuration.
    base = Ai::Agent.for_account(service_account&.id).where(status: "active")
    agent = base.where(slug: slug).account_override_first.first
    agent ||= base.where(name: fallback_name).account_override_first.first if fallback_name
    agent&.using_account(service_account)
  end

  # Build a WorkerLlmClient that routes through the agent's provider config.
  # The worker resolves the provider and credential from the agent_id.
  #
  # By default, wraps the client in TrackedWorkerLlmClient which creates
  # Ai::AgentExecution records for every LLM call (complete, complete_structured,
  # complete_with_tools). Pass tracked: false for raw access.
  def build_agent_client(agent, tracked: true)
    # When tracked=true, budget tracking is handled by the AgentExecution
    # callback (propagate_cost_to_budget), so skip it in the inner client
    # to prevent double-debiting.
    client = WorkerLlmClient.new(agent_id: agent.id, skip_budget_tracking: tracked)
    return client unless tracked

    TrackedWorkerLlmClient.new(
      inner_client: client,
      agent: agent,
      execution_context_type: "service:#{self.class.name}"
    )
  end

  # Resolve model from the agent's selection triple (#37): pinned model, else the
  # cost/capability selector pick across any active provider, else provider default.
  def agent_model(agent)
    agent.resolved_model
  end

  # Agent's system prompt (with conversation profile merged in).
  def agent_system_prompt(agent)
    agent.build_system_prompt_with_profile
  end

  # Temperature from agent mcp_metadata model_config, defaults to 0.7
  def agent_temperature(agent)
    (agent.mcp_metadata&.dig("model_config", "temperature") || 0.7).to_f
  end

  # Max tokens from agent mcp_metadata model_config, defaults to 2048
  def agent_max_tokens(agent)
    (agent.mcp_metadata&.dig("model_config", "max_tokens") || 2048).to_i
  end

  # Account accessor — services may use @account, account, or other patterns.
  def service_account
    if respond_to?(:account, true) && !is_a?(ActiveRecord::Base)
      account
    else
      @account
    end
  end

  # Governed per-task tier resolution (campaign 019f2163 inc4) for
  # AgentBackedService callers whose LLM calls bypass the TaskExecutor /
  # ProviderExecution seams entirely (bulk/background utility calls — KG
  # extraction, context compression, LLM-judge scoring — that have no
  # escalation basis of their own). Mirrors the exact gated pattern those two
  # seams use: behind the account gate `ai_task_tier_routing_enabled` (default
  # OFF ⇒ this returns nil immediately, no resolver call at all — callers fall
  # back to their pre-existing baseline model resolution byte-identically). ON,
  # resolves + persists a governance record (Ai::RoutingDecision +
  # Ai::TaskComplexityAssessment) for the given explicit task_type and returns
  # the Resolution, or nil on any resolver failure.
  def resolve_task_tier(agent:, task_type:, messages:, tools: [])
    # Reset on every call — some callers (e.g. ExtractionService's multi-client
    # fallback loop) invoke this repeatedly on the same instance, and a stale id
    # from a prior successful call must never leak onto a later, unrelated
    # TrackedWorkerLlmClient call when this call's own resolution is skipped or
    # fails.
    @routing_decision_id = nil
    return nil unless ::Ai::Routing::TaskTierResolver.enabled_for?(service_account)

    resolution = ::Ai::Routing::TaskTierResolver.resolve(
      account: service_account, agent: agent, task_type: task_type, messages: messages, tools: tools
    )
    # No Ai::AgentExecution exists yet at this point — callers resolve the tier
    # BEFORE invoking the tracked client (the model/effort feed the LLM call
    # itself). Stash the decision id so it can be handed to build_agent_client's
    # TrackedWorkerLlmClient via routing_decision_id:, which links it to the
    # execution it creates once that call happens (see #routing_decision_id).
    @routing_decision_id = resolution&.persist!&.id
    resolution
  rescue StandardError => e
    Rails.logger.warn("[AgentBackedService] tier routing failed for task_type=#{task_type}: #{e.class}: #{e.message}")
    nil
  end

  # The Ai::RoutingDecision id from the most recent #resolve_task_tier call, for
  # callers to pass as routing_decision_id: into a TrackedWorkerLlmClient call so
  # the resulting Ai::AgentExecution gets linked and the decision's outcome can
  # later be recorded (Ai::AgentExecution#record_routing_decision_outcome).
  def routing_decision_id
    @routing_decision_id
  end

  # --- Discovery internals ---

  # Use SemanticToolDiscoveryService to find agents matching the task.
  # Filters to source: "agent" results and returns the top match.
  def discover_agent_by_task(task_description, account, min_score)
    cache_key = "agent_discovery:#{account.id}:#{Digest::SHA256.hexdigest(task_description)}"
    cached_id = Rails.cache.read(cache_key)

    if cached_id
      agent = Ai::Agent.find_by(id: cached_id, status: "active")
      return agent if agent
    end

    discovery = Ai::Tools::SemanticToolDiscoveryService.new(account: account)
    results = discovery.discover(query: task_description, limit: 5)

    # Filter to agent-type results above the minimum score
    agent_results = results.select { |r| r[:source] == "agent" && r[:relevance_score].to_f >= min_score }
    return nil if agent_results.empty?

    best = agent_results.first
    agent = Ai::Agent.find_by(id: best[:agent_id], status: "active")

    # Cache the winning agent_id for this task description
    Rails.cache.write(cache_key, agent.id, expires_in: DISCOVERY_CACHE_TTL) if agent

    agent
  end
end
