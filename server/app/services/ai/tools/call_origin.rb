# frozen_string_literal: true

module Ai
  module Tools
    # HOW A CALL REACHED A TOOL (MCP identity plan R3).
    #
    # Every MCP-shaped caller goes through Ai::Tools::McpPlatformToolRegistrar,
    # and each names its door here. The registrar sets the value on the tool
    # (BaseTool#call_origin). The mark comes from the door that received the
    # call: Mcp::Principal#call_origin for the streamable controller, and a
    # constant at each in-process funnel. It never comes from whether an agent
    # record could be resolved for the caller.
    #
    # That distinction is the defect this exists for. An OAuth MCP call carries
    # an mcp_client agent only when the account has an active AI provider to
    # back one (Ai::McpClientIdentityService#create_mcp_agent returns nil
    # otherwise, and an account-scoped agent cannot exist without a provider:
    # chk_ai_agents_account_rows_need_creator_and_provider). A check that read
    # "no agent" as "a person" therefore let a no-provider MCP client through a
    # human-only gate (secreview E12).
    #
    # EVERY VALUE IS A MACHINE'S DOOR. A tool call is never a person's consent
    # (R1): the user a call carries is the AUTHORITY its permission checks ask,
    # an agent's creator or the owner of an MCP client's token. There is
    # deliberately no human value, and spec/lint/registrar_origin_spec.rb pins
    # that. A person decides through their own REST/UI session, which never
    # reaches a tool.
    #
    # An unmarked call (nil: a tool constructed directly, as some REST
    # controllers and skill executors do) grants nothing either. It only keeps
    # the behaviour those direct constructions had before the mark existed,
    # and the lint keeps every registrar call site marked.
    module CallOrigin
      # The streamable HTTP door, by the principal the auth concern built.
      MCP_OAUTH      = "mcp_oauth"
      MCP_INSTANCE   = "mcp_instance"
      MCP_FEDERATION = "mcp_federation"
      # The ActionCable MCP channel (Mcp::ProtocolService).
      MCP_CABLE      = "mcp_cable"
      # An agent's own tool-calling loop (Ai::AgentToolBridgeService, and the
      # loop-local tools Ai::Ralph::AgenticLoop dispatches).
      AGENT_BRIDGE   = "agent_bridge"
      # A skill recipe step (Ai::SkillRecipeRunner).
      SKILL_RECIPE   = "skill_recipe"

      # Tools CONSTRUCTED DIRECTLY by a machine-driven caller name their door in
      # the constructor (BaseTool.new(call_origin:), reviewer guidance 3), and
      # spec/lint/registrar_origin_spec.rb keeps every direct construction marked:
      # the concierge acting on a model's reading of a chat message,
      CONCIERGE      = "concierge"
      # an A2A skill serving a peer agent's request,
      A2A            = "a2a"
      # a platform skill executor nesting a tool,
      SKILL_EXECUTOR = "skill_executor"
      # and an in-process system service (discovery runs, learning extractors,
      # orchestrators) acting on its own schedule.
      SYSTEM_SERVICE = "system_service"

      ALL = [ MCP_OAUTH, MCP_INSTANCE, MCP_FEDERATION, MCP_CABLE, AGENT_BRIDGE, SKILL_RECIPE,
              CONCIERGE, A2A, SKILL_EXECUTOR, SYSTEM_SERVICE ].freeze

      module_function

      # True for every defined origin: each names a door a machine uses.
      def machine?(origin)
        ALL.include?(origin.to_s)
      end

      # The origin itself, nil for an unmarked call, and a raise for anything
      # else. A mistyped origin must not pass as "unmarked", because an
      # unmarked call keeps a direct construction's looser treatment.
      def validate!(origin)
        return nil if origin.nil?
        return origin.to_s if machine?(origin)

        raise ArgumentError, "unknown call_origin #{origin.inspect}; expected one of #{ALL.join(', ')} or nil"
      end
    end
  end
end
