# frozen_string_literal: true

module Ai
  module Provisioning
    # Which Ai::Agent the provisioning services attribute their LLM calls to
    # (IMP 019fe1da).
    #
    # These services predate agent-backed execution: they called
    # WorkerLlmClient.for_account directly, so their calls produced no
    # Ai::AgentExecution and were invisible to every routing/cost/context
    # oracle — and, because WorkerLlmClient#track_llm_usage! bails without an
    # @agent_id, could never debit an Ai::AgentBudget either.
    #
    # Ordered by fit, first match wins:
    #   system-topology-designer — owns provisioning/topology reasoning. Seeded
    #     by the SYSTEM EXTENSION, so it is absent in core mode.
    #   intent-classifier        — core-seeded (db/seeds/ai_utility_agents_seed.rb),
    #     the always-available fallback.
    #
    # Shared rather than duplicated per service so the attribution target is one
    # decision in one place; when a dedicated provisioning agent is seeded, this
    # list is the only thing to change.
    #
    # No match is not an error: AgentBackedService#tracked_client_for returns the
    # unwrapped client and the caller keeps working, untracked.
    module TrackingAgents
      SLUGS = %w[system-topology-designer intent-classifier].freeze
    end
  end
end
