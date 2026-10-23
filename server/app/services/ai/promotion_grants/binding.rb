# frozen_string_literal: true

module Ai
  module PromotionGrants
    # What a bound promotion grant (or request) is bound to, and whether a
    # gated call may spend it.
    #
    # The target is resolved SERVER-SIDE, from the calling tool's own state,
    # never from params: the MCP session the call arrived on (owner-resolved by
    # the streamable controller) or the agent execution running the call (set
    # by the agent executor on the tools it builds). A park principal
    # (Ai::Approvals::ParkPrincipal) records the same ids, minted from that
    # same state, and the gate hands it to Ai::PromotionGrants::Ledger.consume!.
    #
    # A bound grant matches a call only when the call's principal carries the
    # grant's target AND the target is live at use time:
    #   mcp_session      principal["mcp_session_id"] names it; the session is
    #                    live (active, unexpired, not idle) and is the
    #                    grant agent's own.
    #   agent_execution  principal["agent_execution_id"] names it; the
    #                    execution is running and is the grant agent's own.
    # So a session-bound grant never matches a call without that session, a
    # run-bound one never matches from a session, and vice versa.
    module Binding
      PRINCIPAL_KEYS = {
        ::Ai::PromotionGrant::BINDING_MCP_SESSION => "mcp_session_id",
        ::Ai::PromotionGrant::BINDING_AGENT_EXECUTION => "agent_execution_id"
      }.freeze

      module_function

      # The live target row for (kind, id), or nil when it is gone or ended.
      def live_target(kind:, id:, account_id:, agent_id:)
        return nil if id.blank?

        case kind.to_s
        when ::Ai::PromotionGrant::BINDING_MCP_SESSION
          session = ::McpSession.find_by(id: id.to_s, account_id: account_id)
          session if session&.live? && session.ai_agent_id.to_s == agent_id.to_s
        when ::Ai::PromotionGrant::BINDING_AGENT_EXECUTION
          execution = ::Ai::AgentExecution.find_by(id: id.to_s, account_id: account_id)
          execution if execution&.running? && execution.ai_agent_id.to_s == agent_id.to_s
        end
      end

      def target_live?(kind:, id:, account_id:, agent_id:)
        live_target(kind: kind, id: id, account_id: account_id, agent_id: agent_id).present?
      end

      # May a call whose park principal is `principal` spend `grant`? An
      # unbound grant: always (the other axes are the ledger's). A bound one:
      # only as the module comment says.
      def matches?(grant, principal)
        return true unless grant.bound?

        key = PRINCIPAL_KEYS[grant.binding_kind.to_s]
        return false if key.nil? || !principal.is_a?(::Hash)

        carried = principal.stringify_keys[key].to_s
        return false if carried.blank? || carried != grant.binding_id.to_s

        target_live?(kind: grant.binding_kind, id: grant.binding_id, account_id: grant.account_id,
                     agent_id: grant.ai_agent_id)
      end

      # A short, operator-readable statement of the binding, for the approval
      # card and the API: "bound to session …", "bound to run … of agent …",
      # or "unbound".
      def describe(kind:, id:, agent: nil)
        case kind.to_s
        when ::Ai::PromotionGrant::BINDING_MCP_SESSION
          "bound to session #{id}"
        when ::Ai::PromotionGrant::BINDING_AGENT_EXECUTION
          "bound to run #{id}#{" of agent #{agent.name}" if agent}"
        else
          "unbound"
        end
      end
    end
  end
end
