# frozen_string_literal: true

module Ai
  # Concierge-specific subclass of AgentToolBridgeService.
  #
  # Three specializations over the base service:
  #   1. Excludes self-referential tools (concierge/conversation tools) to prevent recursion
  #   2. Injects a virtual `request_confirmation` tool for high-risk operations
  #   3. Caps iterations at 8 (synchronous controller path, not background job)
  #
  # The confirmation tool creates the same action-card metadata that the frontend
  # already renders for the legacy action-grammar confirmations, preserving the
  # existing UX without the custom [CONFIRM:...] grammar.
  #
  class ConciergeToolBridge < AgentToolBridgeService
    CONCIERGE_MAX_ITERATIONS = 8

    # Tools that target the concierge itself — calling them would cause recursion
    SELF_REFERENTIAL_TOOLS = %w[
      send_concierge_message confirm_concierge_action
      list_conversations get_conversation_messages
    ].freeze

    # Autonomy tools the concierge should never use — workspace context already
    # provides agent/session information via WORKSPACE MEMBERS in the system prompt.
    # Keeping these available causes the LLM to call them instead of reading the
    # already-present workspace member list.
    EXCLUDED_AUTONOMY_TOOLS = %w[
      discover_claude_sessions
      request_code_change
    ].freeze

    # In workspace conversations, only expose tools relevant to delegation and monitoring.
    # Reduces tool count from ~84 to ~25, making send_message immediately visible to the LLM.
    WORKSPACE_TOOLS = %w[
      send_message invite_agent list_messages list_workspaces active_sessions
      create_workspace
      list_agents get_agent execute_agent
      list_teams get_team execute_team add_team_member
      search_knowledge query_learnings search_knowledge_graph
      read_shared_memory search_memory
      get_mission_status get_activity_feed get_notifications dismiss_notification
      get_system_health kill_switch_status
    ].freeze

    # Tools that modify significant state and should use confirmation
    HIGH_RISK_TOOLS = %w[
      execute_team execute_workflow execute_agent
      trigger_pipeline dispatch_to_runner create_gitea_repository
    ].freeze

    def initialize(agent:, account:, conversation:, user:)
      super(agent: agent, account: account)
      @conversation = conversation
      @user = user
    end

    # Always enable tools for concierge (bypasses the mcp_client check in base)
    def tools_enabled?
      true
    end

    def max_iterations
      CONCIERGE_MAX_ITERATIONS
    end

    # Intercept the virtual `request_confirmation` tool; delegate everything else.
    # Auto-injects conversation_id for workspace tools — LLMs (especially gpt-4.1-mini)
    # frequently hallucinate conversation IDs instead of extracting the actual UUID
    # from the system prompt.
    WORKSPACE_CONTEXT_TOOLS = %w[send_message list_messages invite_agent].freeze

    def dispatch_tool_call(tool_call)
      tool_name = tool_call[:name] || tool_call["name"]

      if tool_name == "request_confirmation"
        handle_confirmation_request(tool_call)
      else
        if @conversation&.workspace_conversation? && WORKSPACE_CONTEXT_TOOLS.include?(tool_name)
          arguments = tool_call[:arguments] || tool_call["arguments"] || {}
          arguments = JSON.parse(arguments) if arguments.is_a?(String)
          arguments = arguments.stringify_keys.merge("conversation_id" => @conversation.conversation_id)

          # Auto-prepend @mention when the model omits it from send_message.
          # gpt-4.1-mini frequently delegates with just the request text
          # (e.g. "What time is it?") without the required @AgentName prefix.
          if tool_name == "send_message" && arguments["message"].present?
            arguments["message"] = ensure_mention(arguments["message"])
          end

          tool_call = tool_call.merge(arguments: arguments, "arguments" => arguments)
          Rails.logger.info("[ConciergeToolBridge] Auto-injected conversation_id=#{@conversation.conversation_id} into #{tool_name}")
        end
        super(tool_call)
      end
    end

    private

    # Ensure the message contains an @mention for at least one workspace member.
    # If the LLM omitted it, prepend a mention for the default delegation target
    # (first mcp_client agent, or first non-concierge member).
    def ensure_mention(message)
      team = @conversation.agent_team
      return message unless team

      members = team.members.includes(:agent).where.not(ai_agent_id: agent.id)
      return message if members.empty?

      # Check if message already has an @mention for any member.
      # Also match base names without the #N suffix — LLMs frequently write
      # "@Claude Code (powernode)" instead of "@Claude Code (powernode) #1".
      has_mention = members.any? do |m|
        next false unless m.agent
        name = m.agent.name
        next true if message.include?("@#{name}")
        # Strip "#N" suffix and check base name
        base = name.sub(/\s*#\d+\z/, "")
        base != name && message.include?("@#{base}")
      end
      return message if has_mention

      # Pick the default target: prefer mcp_client, then first non-concierge
      target = members.find { |m| m.agent&.agent_type == "mcp_client" }&.agent ||
               members.find { |m| m.agent&.agent_type != "assistant" }&.agent ||
               members.first&.agent
      return message unless target

      Rails.logger.info("[ConciergeToolBridge] Auto-prepended @#{target.name} to send_message")
      "@#{target.name} #{message}"
    end

    # Override: filter self-referential tools and append the confirmation tool
    def build_tool_definitions
      definitions = Ai::Tools::PlatformApiToolRegistry.tool_definitions(agent: agent)
      excluded = SELF_REFERENTIAL_TOOLS + EXCLUDED_AUTONOMY_TOOLS
      definitions = definitions.reject { |d| excluded.include?(d[:name].to_s) }

      # In workspace mode, restrict to delegation-relevant tools only (~25 vs ~84)
      if @conversation&.workspace_conversation?
        definitions = definitions.select { |d| WORKSPACE_TOOLS.include?(d[:name].to_s) }
      end

      llm_tools = definitions.map { |defn| convert_to_llm_tool(defn) }
      llm_tools << confirmation_tool_definition
      llm_tools
    end

    def confirmation_tool_definition
      {
        name: "request_confirmation",
        description: "Request user confirmation before executing a high-risk action. " \
                     "Use this for operations that modify state significantly: executing agents/teams/workflows, " \
                     "triggering pipelines, creating repositories, or any destructive operation. " \
                     "The user will see a confirmation card and can approve or reject the action.",
        parameters: {
          type: "object",
          properties: {
            "action_description" => {
              type: "string",
              description: "Human-readable description of what will happen if confirmed"
            },
            "tool_name" => {
              type: "string",
              description: "The platform tool to execute upon confirmation (e.g. execute_team, trigger_pipeline)"
            },
            "tool_arguments" => {
              type: "object",
              description: "Arguments to pass to the tool when the user confirms",
              additionalProperties: true
            }
          },
          required: %w[action_description tool_name tool_arguments]
        }
      }
    end

    # Creates an action-card message identical to the legacy [CONFIRM:...] flow,
    # but tagged with mode: "tool_bridge" so handle_confirmed_action knows to
    # dispatch via AgentToolBridgeService rather than the hardcoded action handlers.
    def handle_confirmation_request(tool_call)
      arguments = tool_call[:arguments] || tool_call["arguments"] || {}
      arguments = JSON.parse(arguments) if arguments.is_a?(String)

      description = arguments["action_description"]
      tool_name = arguments["tool_name"]
      tool_args = arguments["tool_arguments"] || {}

      @conversation.add_assistant_message(
        description,
        content_metadata: {
          "concierge_action" => true,
          "action_type" => tool_name,
          "action_params" => tool_args.merge("_tool_name" => tool_name),
          "actions" => [
            { "type" => "confirm", "label" => "Confirm", "style" => "primary" },
            { "type" => "modify", "label" => "Modify", "style" => "secondary" }
          ],
          "action_context" => {
            "type" => "concierge_confirmation",
            "action_type" => tool_name,
            "status" => "pending",
            "mode" => "tool_bridge"
          }
        }
      )

      { status: "confirmation_requested", message: "User will be prompted to confirm: #{description}" }.to_json
    end
  end
end
