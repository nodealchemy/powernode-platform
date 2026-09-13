# frozen_string_literal: true

module Ai
  class Agent
    # External MCP server integration for platform-resident agents.
    #
    # Lets an Ai::Agent be attached to account-owned McpServer rows so its runtime
    # (AgentToolBridgeService, driving McpAgentExecutor and ConversationResponseJob)
    # can advertise and invoke those servers' tools. Attachment is opt-in and lives
    # in mcp_metadata["mcp_server_ids"]; it never crosses the account boundary and
    # only surfaces connected servers / enabled tools.
    #
    # Mirrors the pre-existing Ralph accessor pattern
    # (Ai::RalphLoopConcerns::TaskAndLearning#mcp_servers/#available_mcp_tools),
    # which stores the same key in `configuration` rather than `mcp_metadata`.
    module McpServerIntegration
      extend ActiveSupport::Concern

      def mcp_server_ids
        mcp_metadata&.dig("mcp_server_ids") || []
      end

      def mcp_server_ids=(ids)
        self.mcp_metadata = (mcp_metadata || {}).merge("mcp_server_ids" => Array(ids).compact)
      end

      # Attached servers, scoped to this agent's account and to connected status —
      # a disconnected/errored server is invisible so we never advertise a tool we
      # cannot reach. A global agent (account nil) has no external servers.
      #
      # LOAD-BEARING BEYOND THIS FILE (IMP-01a06b9a). The `account.nil?` arm is
      # the only thing keeping a global CANONICAL out of
      # AgentToolBridgeService's external-MCP dispatch branch, which returns
      # before McpPlatformToolRegistrar and so never meets BaseTool's
      # canonical_principal? refusal — its own gates ask about the creator's
      # permissions, never about what kind of agent is acting. Because a
      # canonical resolves no server here, it advertises no external tool and
      # the dispatch fork cannot be taken; it falls through to the platform
      # registrar, where the refusal applies.
      #
      # Widening this to let global agents carry servers therefore needs a
      # canonical guard ON that branch first. Pinned at both ends by
      # spec/services/ai/agent_tool_bridge_canonical_external_mcp_spec.rb.
      def mcp_servers
        return McpServer.none if account.nil? || mcp_server_ids.empty?

        account.mcp_servers.where(id: mcp_server_ids, status: "connected")
      end

      # Enabled tools across the attached, connected servers.
      def available_mcp_tools
        mcp_servers.flat_map { |s| s.mcp_tools.where(enabled: true) }
      end
    end
  end
end
