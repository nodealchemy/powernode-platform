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

    # Confidence threshold for the provisioning intent classifier — below this,
    # we don't auto-bootstrap a mission and let the LLM handle the message
    # through the normal tool-loop path. Above it, we treat the message as an
    # explicit provisioning request and dispatch capture_brief directly.
    PROVISIONING_CONFIDENCE_THRESHOLD = 0.5
    PROVISIONING_INTENT = "provision_infrastructure"

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

    # System Concierge's tool surface (operator chat for the system extension).
    # Owned here rather than in seed metadata because the filter is a runtime
    # contract — adding a new tool family means updating this list, and the
    # bridge is the consumer.
    SYSTEM_CONCIERGE_TOOL_FILTER = %w[
      system_*
      docker_*
      kubernetes_*
      discover_skills
      get_skill_context
      request_confirmation
      execute_agent
      list_agents
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

    # Provisioning intent dispatcher — when the user's message looks like a
    # provisioning request (regex pre-filter inside IntentCaptureService plus
    # an LLM confidence-scoring pass), auto-bootstrap the infrastructure
    # mission via platform_provisioning_capture_brief instead of letting the
    # generic tool loop guess at the right action.
    #
    # Returns the ProvisioningTool result Hash on a hit (caller renders the
    # brief + missing_fields in the conversation), or nil when classification
    # below threshold lets the caller fall through to the standard flow.
    #
    # Existing dispatch_tool_call handlers are untouched — this is an
    # opt-in helper called by the Concierge service before the tool loop.
    def classify_and_dispatch_provisioning(natural_language:)
      return nil if natural_language.to_s.strip.empty?

      classifier = ::Ai::Provisioning::IntentCaptureService.new(
        account: account, user: @user, conversation: @conversation
      )
      classification = classifier.classify(natural_language: natural_language)

      return nil unless classification[:intent_type] == PROVISIONING_INTENT
      return nil unless classification[:confidence].to_f >= PROVISIONING_CONFIDENCE_THRESHOLD

      Rails.logger.info(
        "[ConciergeToolBridge] Provisioning intent detected " \
        "(confidence=#{classification[:confidence]}); dispatching capture_brief"
      )

      tool = ::Ai::Tools::ProvisioningTool.new(
        account: account, agent: agent, user: @user
      )
      tool.execute(params: {
        action: "platform_provisioning_capture_brief",
        natural_language: natural_language
      })
    end

    def dispatch_tool_call(tool_call)
      dispatch_tool_call_capturing(tool_call).first
    end

    # Override the capturing path so the auto-confirmation logic fires whether
    # the loop calls #dispatch_tool_call_capturing directly (the agentic loop
    # path) or #dispatch_tool_call (external callers).
    def dispatch_tool_call_capturing(tool_call)
      tool_name = tool_call[:name] || tool_call["name"]

      if tool_name == "request_confirmation"
        msg = handle_confirmation_request(tool_call)
        return [msg, { handled: true }]
      end

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

      result_json, full_result = super(tool_call)

      # T3 — auto-surface a confirmation card when a tool returns
      # requires_approval + a confirmation block. Removes the reliance on
      # smaller LLMs (gpt-4.1-mini, etc.) choosing to call
      # request_confirmation as a follow-up; the operator sees the
      # interactive card immediately alongside the LLM's narration.
      auto_emit_confirmation(full_result) if full_result.is_a?(Hash)

      [result_json, full_result]
    end

    private

    # Detect tool results carrying { requires_approval: true } + a
    # confirmation: {action_type, action_description, action_params} block
    # and emit a confirmation card the operator can click without waiting
    # on the LLM to call request_confirmation.
    def auto_emit_confirmation(full_result)
      requires_approval = full_result[:requires_approval] || full_result["requires_approval"]
      return unless requires_approval

      data = full_result[:data] || full_result["data"] || {}
      confirmation = if data.is_a?(Hash)
                       data[:confirmation] || data["confirmation"]
                     end
      confirmation ||= full_result[:confirmation] || full_result["confirmation"]
      return unless confirmation.is_a?(Hash)

      synthetic = {
        arguments: {
          "action_description" => confirmation[:action_description] || confirmation["action_description"],
          "tool_name"          => confirmation[:action_type]        || confirmation["action_type"],
          "tool_arguments"     => confirmation[:action_params]      || confirmation["action_params"] || {}
        }
      }
      handle_confirmation_request(synthetic)
      Rails.logger.info(
        "[ConciergeToolBridge] auto-emitted confirmation card action=#{synthetic[:arguments]['tool_name']}"
      )
    rescue StandardError => e
      Rails.logger.error("[ConciergeToolBridge] auto-confirmation failed: #{e.class}: #{e.message}")
    end

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
      elsif (patterns = agent_tool_filter_patterns).any?
        # Agent-declared tool surface — extension agents (e.g., System Concierge,
        # SDWAN Concierge) restrict the LLM to a curated tool slice via
        # agent.metadata["concierge_tool_filter"] — patterns are tool-name
        # prefixes or exact names. Avoids hardcoding extension-specific names
        # in the platform-level bridge.
        definitions = definitions.select { |d| tool_matches_patterns?(d[:name].to_s, patterns) }
      end

      llm_tools = definitions.map { |defn| convert_to_llm_tool(defn) }
      llm_tools << confirmation_tool_definition
      llm_tools
    end

    # Reads the agent's declared tool filter (from metadata). Patterns can be
    # exact tool names or prefix patterns ending in "*" (e.g. "system_*").
    # Empty / missing = no agent-driven filter (default tool surface applies).
    def agent_tool_filter_patterns
      meta = agent&.metadata
      return [] unless meta.is_a?(Hash)

      # System Concierge: filter is owned by this bridge (single source of
      # truth for the canonical operator chat agent).
      return SYSTEM_CONCIERGE_TOOL_FILTER if meta["concierge_kind"] == "system_concierge"

      # Other concierge-style extension agents (e.g. Topology Designer)
      # declare their filter in metadata.
      patterns = meta["concierge_tool_filter"] || meta[:concierge_tool_filter]
      Array(patterns).map(&:to_s).reject(&:empty?)
    end

    def tool_matches_patterns?(tool_name, patterns)
      patterns.any? do |pattern|
        if pattern.end_with?("*")
          tool_name.start_with?(pattern.chomp("*"))
        else
          tool_name == pattern
        end
      end
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
