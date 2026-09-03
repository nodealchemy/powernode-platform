# frozen_string_literal: true

module Ai
  module Routing
    # THE ONE DEFINITION of "routable agent" (HIER-P1B item 10), shared by the
    # Claude Code exporter (Ai::ClaudeExport::AgentSkeletonSync) and the
    # platform router (Ai::Routing::AgentRouterService) so both sides route
    # over — and name — the same set.
    #
    # Routable = active, not an mcp_client identity (those are ephemeral
    # per-session rows auto-created by Ai::McpClientIdentityService, with no
    # prompt worth routing to — AgentToolBridgeService#tools_enabled? draws the
    # same line), deduplicated by key with the account's own row winning over a
    # same-slug canonical (Ai::Agent.resolve_for's override rule).
    #
    # Three views:
    #   .canonical         GLOBAL is_system rows — the committed CC export and
    #                      what "official platform agent" means (canonical rule).
    #   .owned_by(account) the account's own rows only (clones + own agents) —
    #                      the local, gitignored CC export.
    #   .for(account_id)   canonical ∪ own, override-aware — what the router
    #                      ranks inside an account.
    module RoutableAgents
      module_function

      def canonical
        dedupe(base.merge(::Ai::Agent.global).where(is_system: true))
      end

      def owned_by(account_id)
        return [] if account_id.blank?

        dedupe(base.merge(::Ai::Agent.owned_by_account(account_id)))
      end

      def for(account_id)
        return canonical if account_id.blank?

        dedupe(base.merge(::Ai::Agent.for_account(account_id)).account_override_first)
      end

      # Filesystem-safe, unique-across-the-set identifier; doubles as the Claude
      # Code `subagent_type`. The slug is presence/format-validated at the model
      # level, so the fallbacks only guard a defensive edge case (legacy blank slug).
      def key(agent)
        agent.slug.presence || agent.name.to_s.parameterize.presence || "agent-#{agent.id}"
      end

      def base
        ::Ai::Agent.active.where.not(agent_type: "mcp_client")
      end

      # One row per key; relies on the caller's ordering to decide which row of
      # a same-key pair survives (account_override_first puts the account's first).
      def dedupe(scope)
        scope.to_a
             .group_by { |agent| key(agent) }
             .transform_values(&:first)
             .values
             .sort_by { |agent| key(agent) }
      end
    end
  end
end
