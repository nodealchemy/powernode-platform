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
    #   * Ai::ClaudeExport::ToolAllowlist — the committed Claude Code `tools:`
    #     allowlist, which unions this set plus its own self-report verb.
    # route_task is in the set for the same reason the others are: it is the
    # MCP face of Ai::Routing::AgentRouterService, the one router both the
    # Concierge and a Claude Code skeleton delegate through.
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
        discover_skills
        get_skill_context
        search_knowledge
        query_learnings
        code_semantic_search
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
