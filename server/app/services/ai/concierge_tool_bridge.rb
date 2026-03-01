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

    # Intercept the virtual `request_confirmation` tool; delegate everything else
    def dispatch_tool_call(tool_call)
      tool_name = tool_call[:name] || tool_call["name"]

      if tool_name == "request_confirmation"
        handle_confirmation_request(tool_call)
      else
        super
      end
    end

    private

    # Override: filter self-referential tools and append the confirmation tool
    def build_tool_definitions
      definitions = Ai::Tools::PlatformApiToolRegistry.tool_definitions(agent: agent)
      definitions = definitions.reject { |d| SELF_REFERENTIAL_TOOLS.include?(d[:name].to_s) }

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
