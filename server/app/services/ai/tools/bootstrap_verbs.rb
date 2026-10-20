# frozen_string_literal: true

module Ai
  module Tools
    # THE ONE bootstrap allowlist (HIER-P2H): the read-only platform verbs every
    # agent is served whatever its tool_families scope, because
    # Ai::Agent::BASE_GUARDRAILS — prepended to every agent prompt — orders the
    # agent to call them ("query platform guidance (search_knowledge
    # tag:guidance-*)", "Reuse first: … discover_skills / search_knowledge /
    # code_semantic_search"), and a skeleton or a runtime tool list that omits
    # them leaves the agent unable to obey its own guardrails.
    #
    # Two consumers read this constant and nothing else, so the platform's
    # runtime tool list and the Claude Code skeleton of the same agent cannot
    # disagree about what it always has:
    #   * Ai::AgentToolBridgeService — the RUNTIME door, on BOTH of its scoping
    #     branches: #scope_to_tool_families (before this a plain family select,
    #     so any agent with a configured tool_families list lost these verbs
    #     while its prompt kept demanding them — the Ingress seed listed them
    #     per agent as a workaround; the sibling wave-2 seeds did not) and the
    #     explicit-allowed_tools branch of #platform_tool_definitions, which
    #     the exporter has always unioned onto and the bridge did not;
    #   * Ai::ClaudeExport::ToolAllowlist — the account-scope Claude Code
    #     `tools:` allowlist, which unions this set plus its own self-report verb
    #     (the committed C4 thin loaders name their own fixed core,
    #     Ai::ClaudeExport::ThinLoader::BOOTSTRAP_ACTIONS).
    # route_task is in the set for the same reason the others are: it is the
    # MCP face of Ai::Routing::AgentRouterService, the one router both the
    # Concierge and a Claude Code skeleton delegate through.
    # assemble_task (skills-first agents, PRE-2) is the first thing an agent does
    # with a task: the skills, learnings and verb lists that own it, and the
    # tier / model / effort to run at. It is declared `mutating: false` — its
    # only write is its own idempotent assembly record, it acts on nothing.
    # discover_tools (C3-3) is how an agent scoped to a few families finds a
    # verb outside them by intent; describe_tool then loads that verb's schema.
    #
    # READ-ONLY BY CONTRACT. Every entry must be declared `mutating: false`
    # under the name that actually dispatches (McpPlatformToolRegistrar::
    # ACTION_ALIASES); spec/services/ai/tools/bootstrap_verbs_spec.rb asserts
    # that through the declaration itself, so a write cannot be added to the
    # set every agent receives without that failing. The exporter's
    # record_agent_execution is a write and therefore lives beside this set,
    # not in it. Membership is a SCOPING decision, never an authorization one:
    # the bridge unions these into definitions that are already permission-
    # filtered, and a verb the agent may not call is not conjured back.
    module BootstrapVerbs
      ACTIONS = %w[
        get_agent
        assemble_task
        discover_skills
        get_skill_context
        search_knowledge
        query_learnings
        code_semantic_search
        discover_tools
        describe_tool
        route_task
      ].freeze

      module_function

      # @param name [String, Symbol] a registry action name
      def include?(name)
        ACTIONS.include?(name.to_s)
      end
    end
  end
end
