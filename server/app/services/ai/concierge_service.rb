# frozen_string_literal: true

module Ai
  class ConciergeService
    INTENTS = %w[create_mission check_status analyze_repo approve_action question delegate_to_team code_review deploy general_chat].freeze
    CONFIRM_REQUIRED = %w[create_mission delegate_to_team code_review deploy].freeze

    # Provider types that support function/tool calling
    TOOL_CAPABLE_PROVIDERS = %w[openai anthropic].freeze

    def initialize(conversation:, user:)
      @conversation = conversation
      @agent = conversation.agent
      @user = user
      @account = user.account
    end

    # Primary entry point — routes to tool-bridge or legacy action-grammar
    def process_message(content)
      credential = find_credential

      if credential && tool_bridge_available?(credential)
        process_with_tools(content, credential)
      else
        process_with_action_grammar(content, credential)
      end
    rescue StandardError => e
      Rails.logger.error("[ConciergeService] Error: #{e.message}")
      @conversation.add_assistant_message(
        "I encountered an error processing your request. Please try again."
      )
    end

    def handle_confirmed_action(action_type, params)
      resolve_pending_action(action_type)

      # Tool-bridge confirmations carry the _tool_name marker
      if params["_tool_name"].present?
        handle_tool_bridge_confirmation(params)
        return
      end

      case action_type
      when "create_mission"
        create_mission(params)
      when "delegate_to_team"
        delegate_to_team(params)
      when "code_review"
        trigger_code_review(params)
      when "deploy"
        trigger_deploy(params)
      else
        @conversation.add_assistant_message("Unknown action type: #{action_type}")
      end
    rescue StandardError => e
      Rails.logger.error("[ConciergeService] Confirmed action error: #{e.message}")
      @conversation.add_assistant_message("Failed to execute action: #{e.message}")
    end

    def post_mission_update(mission, event_type, data = {})
      return unless @conversation

      message = case event_type
      when "phase_changed"
        phase = data[:phase] || data["phase"]
        progress = data[:phase_progress] || data["phase_progress"]
        "Mission **#{mission.name}** entered **#{phase}** phase (#{progress}% complete)"
      when "approval_required"
        gate = data[:gate] || data["gate"]
        "Mission **#{mission.name}** is awaiting **#{gate&.humanize}** — review and approve to proceed"
      when "completed"
        "Mission **#{mission.name}** completed successfully! #{data[:summary] || ''}"
      when "failed"
        "Mission **#{mission.name}** failed: #{data[:error] || 'Unknown error'}"
      else
        return
      end

      @conversation.add_system_message(message, content_metadata: {
        "activity_type" => "mission_#{event_type}",
        "mission_id" => mission.id,
        "mission_name" => mission.name
      })
    end

    private

    # =========================================================================
    # Tool-bridge path (primary — for OpenAI/Anthropic providers)
    # =========================================================================

    # Detect explicit delegation intent: "ask Claude ...", "tell X ...", "have X do ..."
    DELEGATION_PATTERN = /\b(ask|tell|have|message|ping|notify)\s+(claude|the\s+assistant)/i

    def process_with_tools(content, _credential = nil)
      llm_client = WorkerLlmClient.new(agent_id: @agent.id)
      tool_bridge = Ai::ConciergeToolBridge.new(
        agent: @agent, account: @account,
        conversation: @conversation, user: @user
      )

      messages = build_tool_messages(content)
      model = concierge_model || credential.provider.default_model

      # When the user explicitly asks to delegate, force the model to call send_message
      # rather than letting it decide (gpt-4.1-mini often ignores tool-use instructions)
      opts = { temperature: 0.3, max_tokens: 4096, system_prompt: concierge_tool_system_prompt }
      if @conversation.workspace_conversation? && content.match?(DELEGATION_PATTERN)
        opts[:tool_choice] = { "type" => "function", "function" => { "name" => "send_message" } }
        Rails.logger.info("[ConciergeService] Delegation intent detected — forcing send_message tool_choice")
      end

      result = tool_bridge.execute_tool_loop(
        llm_client: llm_client, messages: messages, model: model,
        **opts
      )

      # When the concierge delegated via send_message, the tool call already
      # created a visible message in the conversation. Suppress the LLM's
      # final text to avoid a duplicate/redundant answer.
      # IMPORTANT: Only suppress if the send_message call actually succeeded —
      # a failed send_message means no message was persisted and we must fall
      # through to show the LLM's text response.
      delegated = result[:tool_calls_log]&.any? do |tc|
        tc[:tool] == "send_message" &&
          !tc[:result_preview].to_s.include?('"success":false') &&
          !tc[:result_preview].to_s.include?('"error"')
      end

      if delegated
        Rails.logger.info("[ConciergeService] Delegation detected via send_message (success) — suppressing final text response")
      elsif result[:content].present?
        @conversation.add_assistant_message(
          result[:content],
          processing_metadata: {
            mode: "tool_bridge",
            tool_calls: result[:tool_calls_log].presence,
            usage: result[:usage]
          }.compact
        )
      end
    rescue StandardError => e
      Rails.logger.warn("[ConciergeService] Tool bridge failed, falling back: #{e.message}")
      process_with_action_grammar(content, find_credential)
    end

    def tool_bridge_available?(credential)
      return false unless @agent&.persisted?
      return false unless credential&.provider

      TOOL_CAPABLE_PROVIDERS.include?(credential.provider.provider_type)
    end

    def build_tool_messages(user_content)
      messages = []

      @conversation.messages.not_deleted.ordered.last(15).each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      messages << { role: "user", content: user_content }
      messages
    end

    def concierge_tool_system_prompt
      parts = []

      # Static prompt from the agent's DB record (editable via API/UI)
      # Pass workspace context to filter skills (only workspace-tagged skills in workspace mode)
      ctx = @conversation.workspace_conversation? ? :workspace : nil
      base_prompt = @agent&.build_system_prompt_with_profile(context: ctx).presence
      parts << base_prompt if base_prompt

      # Dynamic runtime context (live data: missions, repos, teams, workspace members)
      context_section = build_context_section
      parts << context_section

      assembled = parts.join("\n\n")

      # Diagnostic logging — helps verify skill injection and workspace context
      has_skill_prompts = assembled.include?("MANDATORY RULE") || assembled.include?("HOW TO DELEGATE")
      has_workspace_context = assembled.include?("CURRENT WORKSPACE:")
      has_delegation_block = assembled.include?("TO SEND A MESSAGE TO AN AGENT")
      Rails.logger.info(
        "[ConciergeService] System prompt assembled: " \
        "length=#{assembled.length} " \
        "has_base_prompt=#{base_prompt.present?} " \
        "base_prompt_length=#{base_prompt&.length || 0} " \
        "has_skill_prompts=#{has_skill_prompts} " \
        "has_delegation_block=#{has_delegation_block} " \
        "has_workspace_context=#{has_workspace_context}"
      )

      assembled
    end

    # =========================================================================
    # Action-grammar path (fallback — for Ollama and non-tool providers)
    # =========================================================================

    def process_with_action_grammar(content, credential = nil)
      response_text = call_concierge_legacy(content, credential)
      action, body = parse_action(response_text)

      case action
      when :confirm
        handle_confirm(body)
      when :action
        execute_action(body)
      else
        handle_respond(body)
      end
    end

    def call_concierge_legacy(content, credential = nil)
      credential ||= find_credential
      unless credential
        return "[RESPOND] I'm unable to process your request right now — no AI provider is configured."
      end

      client = WorkerLlmClient.new(agent_id: @agent.id)
      messages = build_legacy_messages(content)
      model = concierge_model || credential.provider.default_model

      response = client.complete(messages: messages, model: model, max_tokens: 2048, temperature: 0.3)

      if response.success?
        response.content
      else
        Rails.logger.warn("[ConciergeService] LLM call failed: #{response.raw_response&.dig(:error)}")
        "[RESPOND] I'm having trouble processing your request right now. Please try again."
      end
    end

    def build_legacy_messages(user_content)
      messages = []
      messages << { role: "system", content: legacy_system_prompt }

      @conversation.messages.not_deleted.ordered.last(10).each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      messages << { role: "user", content: user_content }
      messages
    end

    def legacy_system_prompt
      parts = []

      # Static prompt from the agent's DB record (editable via API/UI)
      ctx = @conversation.workspace_conversation? ? :workspace : nil
      base_prompt = @agent&.build_system_prompt_with_profile(context: ctx).presence
      parts << base_prompt if base_prompt

      # Dynamic runtime context (live data: missions, repos, teams, workspace members)
      parts << build_context_section

      # Action-grammar markers — tightly coupled to parse_action, must stay in code
      parts << <<~INSTRUCTIONS
        Based on the user's message, respond with ONE of these markers:

        [RESPOND] message — Reply directly when you can answer without taking action.
        [ACTION:check_status] — Query and report on active missions, teams, or executions.
        [ACTION:analyze_repo] repo_name — Trigger repository analysis.
        [ACTION:approve_action] gate_info — Handle an approval gate response.
        [ACTION:question] — Answer a question using your knowledge.
        [CONFIRM:create_mission] {"name": "...", "repository": "...", "objective": "...", "mission_type": "development"} — Propose creating a mission (requires user confirmation).
        [CONFIRM:delegate_to_team] {"team": "...", "objective": "..."} — Propose delegating to a team (requires user confirmation).
        [CONFIRM:code_review] {"repository": "...", "branch": "..."} — Propose a code review (requires user confirmation).
        [CONFIRM:deploy] {"mission_id": "..."} — Propose deployment (requires user confirmation).

        Always start your response with exactly one marker. For CONFIRM actions, include a human-readable description after the JSON.
      INSTRUCTIONS

      parts.join("\n\n")
    end

    # =========================================================================
    # Shared context builder (used by both paths)
    # =========================================================================

    def build_context_section
      parts = []

      # Active missions
      active_missions = @account.ai_missions.in_progress.limit(5)
      if active_missions.any?
        mission_lines = active_missions.map { |m| "- #{m.name} (#{m.mission_type}, phase: #{m.current_phase}, #{m.phase_progress}% complete)" }
        parts << "ACTIVE MISSIONS:\n#{mission_lines.join("\n")}"
      else
        parts << "ACTIVE MISSIONS: None currently active"
      end

      # Available repos
      repos = Devops::GitRepository.where(account_id: @account.id).limit(10)
      if repos.any?
        repo_lines = repos.map { |r| "- #{r.full_name}" }
        parts << "AVAILABLE REPOSITORIES:\n#{repo_lines.join("\n")}"
      end

      # Available teams
      teams = @account.ai_agent_teams.active.limit(10)
      if teams.any?
        team_lines = teams.map { |t| "- #{t.name} (#{t.team_type})" }
        parts << "AVAILABLE TEAMS:\n#{team_lines.join("\n")}"
      end

      # Available agents (exclude the concierge itself)
      agents = @account.ai_agents.active.where.not(id: @agent&.id).limit(10)
      if agents.any?
        agent_lines = agents.map { |a| "- #{a.name} (#{a.agent_type})" }
        parts << "AVAILABLE AGENTS:\n#{agent_lines.join("\n")}"
      end

      # Workspace context (when in a workspace conversation)
      # Behavioral instructions come from the Powernode Concierge skill (injected via
      # build_system_prompt_with_profile). This section provides runtime data only.
      if @conversation.workspace_conversation? && @conversation.agent_team
        team = @conversation.agent_team
        workspace_lines = []
        workspace_lines << "CURRENT WORKSPACE: \"#{team.name}\" (conversation_id: #{@conversation.conversation_id})"

        # Unified WORKSPACE MEMBERS header — all participants under one section
        member_lines = []

        # Human participants
        human_users = [@conversation.user].compact
        if @conversation.is_collaborative? && @conversation.participants.any?
          human_users += User.where(id: @conversation.participants).where.not(id: human_users.map(&:id)).to_a
        end
        human_users.each { |u| member_lines << "- #{u.full_name} (human)" }

        # Agent members (type label helps the LLM understand capabilities)
        members = team.members.includes(:agent).where.not(ai_agent_id: @agent&.id)
        members.each do |m|
          next unless m.agent
          type_label = m.agent.agent_type == "mcp_client" ? "mcp_client" : "server"
          member_lines << "- #{m.agent.name} (#{type_label}, role: #{m.role})"
        end

        workspace_lines << "WORKSPACE MEMBERS:\n#{member_lines.join("\n")}" if member_lines.any?

        # Delegation instructions — immediately after member list (proximity principle)
        if members.any?
          mcp_agent = members.find { |m| m.agent&.agent_type == "mcp_client" }&.agent
          example_agent = mcp_agent || members.first&.agent
          workspace_lines << <<~DELEGATION.strip
            TO SEND A MESSAGE TO AN AGENT, call the send_message tool with:
              message: "@#{example_agent&.name} <your request>"
            The conversation_id is auto-filled — do NOT provide it.
            #{mcp_agent ? "\"Claude\" or \"Claude Code\" = @#{mcp_agent.name}" : ""}
            You HAVE access to all agents above via send_message. NEVER say you cannot communicate with them.
          DELEGATION
        end

        parts << workspace_lines.join("\n\n")
        Rails.logger.info("[ConciergeService] Workspace context included: team=#{team.name} humans=#{human_users.size} agents=#{members.size}")
      else
        is_workspace = @conversation.workspace_conversation?
        has_team = @conversation.agent_team.present?
        Rails.logger.info("[ConciergeService] Workspace context skipped: workspace_conversation=#{is_workspace} has_agent_team=#{has_team}")
      end

      parts.join("\n\n")
    end

    # =========================================================================
    # Tool-bridge confirmation handler
    # =========================================================================

    def handle_tool_bridge_confirmation(params)
      tool_name = params.delete("_tool_name")
      tool_bridge = Ai::AgentToolBridgeService.new(agent: @agent, account: @account)

      result_json = tool_bridge.dispatch_tool_call(name: tool_name, arguments: params)
      result = JSON.parse(result_json)

      if result["error"]
        @conversation.add_assistant_message("Action failed: #{result['message'] || result['error']}")
      else
        @conversation.add_assistant_message("Done! #{summarize_tool_result(tool_name, result)}")
      end
    rescue JSON::ParserError
      @conversation.add_assistant_message("Action completed.")
    end

    def summarize_tool_result(tool_name, result)
      # Provide a human-friendly summary based on the tool type
      case tool_name
      when /^execute_/
        result["status"] ? "Status: #{result['status']}" : "Execution started."
      when /^create_/
        id = result["id"] || result["data"]&.dig("id")
        id ? "Created successfully (ID: #{id})" : "Created successfully."
      when /^trigger_/
        "Pipeline triggered."
      when "dispatch_to_runner"
        "Job dispatched to runner."
      else
        "Completed successfully."
      end
    end

    # =========================================================================
    # Legacy action handlers (used by action-grammar path)
    # =========================================================================

    def parse_action(response_text)
      text = response_text.to_s.strip

      if text.match?(/^\[CONFIRM:(\w+)\]/)
        match = text.match(/^\[CONFIRM:(\w+)\]\s*(.*)$/m)
        intent = match[1]
        body = match[2].strip

        # Try to extract JSON params
        json_match = body.match(/\{[^}]+\}/m)
        params = json_match ? (JSON.parse(json_match[0]) rescue {}) : {}
        description = body.sub(/\{[^}]*\}/m, "").strip
        description = body if description.blank?

        [:confirm, { intent: intent, params: params, description: description }]
      elsif text.match?(/^\[ACTION:(\w+)\]/)
        match = text.match(/^\[ACTION:(\w+)\]\s*(.*)$/m)
        intent = match[1]
        body = match[2].strip
        [:action, { intent: intent, body: body }]
      elsif text.start_with?("[RESPOND]")
        [:respond, text.sub("[RESPOND]", "").strip]
      else
        [:respond, text]
      end
    end

    def handle_respond(message)
      @conversation.add_assistant_message(message)
    end

    def handle_confirm(data)
      intent = data[:intent]
      params = data[:params]
      description = data[:description]

      @conversation.add_assistant_message(
        description.presence || "I'd like to #{intent.humanize.downcase}. Shall I proceed?",
        content_metadata: {
          "concierge_action" => true,
          "action_type" => intent,
          "action_params" => params,
          "actions" => [
            { "type" => "confirm", "label" => "Confirm", "style" => "primary" },
            { "type" => "modify", "label" => "Modify", "style" => "secondary" }
          ],
          "action_context" => {
            "type" => "concierge_confirmation",
            "action_type" => intent,
            "status" => "pending"
          }
        }
      )
    end

    def execute_action(data)
      case data[:intent]
      when "check_status"
        check_status
      when "analyze_repo"
        analyze_repo(data[:body])
      when "approve_action"
        handle_approval(data[:body])
      when "question"
        @conversation.add_assistant_message(data[:body])
      else
        @conversation.add_assistant_message(data[:body].presence || "Action completed.")
      end
    end

    def check_status
      missions = @account.ai_missions.in_progress.order(updated_at: :desc).limit(10)

      if missions.empty?
        @conversation.add_assistant_message("No active missions right now. Would you like to create one?")
        return
      end

      lines = missions.map do |m|
        status_emoji = m.awaiting_approval? ? "⏳" : "🔄"
        "#{status_emoji} **#{m.name}** — #{m.current_phase&.humanize} (#{m.phase_progress}%)"
      end

      summary = "Here are your active missions:\n\n#{lines.join("\n")}"
      @conversation.add_assistant_message(summary)
    end

    def analyze_repo(repo_identifier)
      repo = find_repository(repo_identifier)
      unless repo
        @conversation.add_assistant_message("I couldn't find a repository matching \"#{repo_identifier}\". Available repositories: #{available_repo_names.join(', ')}")
        return
      end

      mission = @account.ai_missions.create!(
        name: "Analysis: #{repo.full_name}",
        mission_type: "research",
        status: "draft",
        repository: repo,
        objective: "Analyze repository structure and capabilities",
        created_by: @user
      )

      service = Ai::Missions::RepoAnalysisService.new(mission: mission)
      result = service.analyze!

      analysis_text = format_analysis_result(result, repo)
      @conversation.add_assistant_message(analysis_text)

      mission.update!(status: "completed", completed_at: Time.current)
    rescue StandardError => e
      @conversation.add_assistant_message("Repository analysis failed: #{e.message}")
    end

    def create_mission(params)
      repo = find_repository(params["repository"])
      unless repo
        @conversation.add_assistant_message("Repository \"#{params['repository']}\" not found.")
        return
      end

      mission = @account.ai_missions.create!(
        name: params["name"] || "Mission: #{params['objective']&.truncate(50)}",
        mission_type: params["mission_type"] || "development",
        repository: repo,
        objective: params["objective"],
        description: params["description"],
        created_by: @user,
        conversation: @conversation
      )

      orchestrator = Ai::Missions::OrchestratorService.new(mission: mission)
      orchestrator.start!

      @conversation.add_system_message(
        "Mission **#{mission.name}** created and started! Currently in **#{mission.current_phase}** phase.",
        content_metadata: {
          "activity_type" => "mission_phase_changed",
          "mission_id" => mission.id,
          "mission_name" => mission.name
        }
      )
    end

    def delegate_to_team(params)
      team = @account.ai_agent_teams.active.find_by(name: params["team"])
      unless team
        @conversation.add_assistant_message("Team \"#{params['team']}\" not found or inactive.")
        return
      end

      @conversation.add_system_message("Delegating to team **#{team.name}**: #{params['objective']}")

      WorkerJobService.enqueue_ai_team_execution(
        team_id: team.id,
        user_id: @user.id,
        input: { task: params["objective"] },
        context: { conversation_id: @conversation.id, source: "concierge" }
      )
    end

    def trigger_code_review(params)
      @conversation.add_assistant_message(
        "Code review requested for **#{params['repository']}** (branch: #{params['branch'] || 'default'}). " \
        "This will be routed through the Code Factory review pipeline."
      )
    end

    def trigger_deploy(params)
      mission = @account.ai_missions.find_by(id: params["mission_id"])
      unless mission
        @conversation.add_assistant_message("Mission not found.")
        return
      end

      @conversation.add_assistant_message(
        "Deployment requested for mission **#{mission.name}**. " \
        "The mission must be in the deploying phase for deployment to proceed."
      )
    end

    def handle_approval(body)
      @conversation.add_assistant_message("Approval handling noted. Please use the mission detail page for formal approvals.")
    end

    # =========================================================================
    # Shared helpers
    # =========================================================================

    def find_repository(identifier)
      return nil if identifier.blank?
      Devops::GitRepository.where(account_id: @account.id)
        .where("full_name ILIKE ? OR name ILIKE ?", "%#{identifier}%", "%#{identifier}%")
        .first
    end

    def available_repo_names
      Devops::GitRepository.where(account_id: @account.id).limit(5).pluck(:full_name)
    end

    def format_analysis_result(result, repo)
      parts = ["## Repository Analysis: #{repo.full_name}\n"]

      if result.is_a?(Hash)
        if result["tech_stack"].present?
          parts << "**Tech Stack**: #{Array(result['tech_stack']).join(', ')}"
        end
        if result["file_count"].present?
          parts << "**Files**: #{result['file_count']}"
        end
        if result["feature_suggestions"].is_a?(Array) && result["feature_suggestions"].any?
          parts << "\n**Feature Suggestions**:"
          result["feature_suggestions"].each_with_index do |s, i|
            title = s.is_a?(Hash) ? s["title"] || s["name"] : s.to_s
            parts << "#{i + 1}. #{title}"
          end
        end
      end

      parts.join("\n")
    end

    def resolve_pending_action(action_type)
      message = @conversation.messages
                                .where(role: "assistant")
                                .order(created_at: :desc)
                                .find { |m|
                                  m.content_metadata&.dig("concierge_action") &&
                                    m.content_metadata&.dig("action_context", "status") == "pending" &&
                                    m.content_metadata&.dig("action_context", "action_type") == action_type
                                }

      return unless message

      updated_metadata = message.content_metadata.deep_dup
      updated_metadata["action_context"]["status"] = "confirmed"
      updated_metadata["action_context"]["resolved_at"] = Time.current.iso8601
      message.update!(content_metadata: updated_metadata)
    end

    def find_credential
      if @agent&.provider
        @agent.provider.provider_credentials
          .where(is_active: true, account_id: @account.id)
          .first
      else
        Ai::ProviderCredential.where(is_active: true, account_id: @account.id).first
      end
    end

    def concierge_model
      @agent&.model || @agent&.mcp_tool_manifest&.dig("model")
    end

    def extract_response_text(response)
      return response.to_s unless response.is_a?(Hash)

      response.dig(:choices, 0, :message, :content) ||
        response[:content]&.then { |c| c.is_a?(Array) ? c.select { |b| b[:type] == "text" }.map { |b| b[:text] }.join("\n") : c } ||
        response[:text] || response.to_s
    end
  end
end
