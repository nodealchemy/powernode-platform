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
    scope = Ai::Agent.where(account: service_account, status: "active")
    agent = scope.find_by(slug: slug)
    agent ||= scope.find_by(name: fallback_name) if fallback_name
    agent
  end

  # Build a WorkerLlmClient that routes through the agent's provider config.
  # The worker resolves the provider and credential from the agent_id.
  #
  # By default, wraps the client in TrackedWorkerLlmClient which creates
  # Ai::AgentExecution records for every LLM call (complete, complete_structured,
  # complete_with_tools). Pass tracked: false for raw access.
  def build_agent_client(agent, tracked: true)
    client = WorkerLlmClient.new(agent_id: agent.id)
    return client unless tracked

    TrackedWorkerLlmClient.new(
      inner_client: client,
      agent: agent,
      execution_context_type: "service:#{self.class.name}"
    )
  end

  # Resolve model from agent configuration.
  # Priority: mcp_metadata model_config > provider default_model
  def agent_model(agent)
    agent.mcp_metadata&.dig("model_config", "model") ||
      agent.provider&.default_model
  end

  # Agent's system prompt (with conversation profile merged in).
  def agent_system_prompt(agent)
    agent.build_system_prompt_with_profile.presence ||
      agent.mcp_metadata&.dig("system_prompt")
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
