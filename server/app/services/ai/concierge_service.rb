# frozen_string_literal: true

module Ai
  class ConciergeService
    INTENTS = %w[create_mission check_status analyze_repo approve_action question delegate_to_team code_review deploy general_chat].freeze
    CONFIRM_REQUIRED = %w[create_mission delegate_to_team code_review deploy].freeze

    def initialize(conversation:, user:)
      @conversation = conversation
      @agent = conversation.agent
      @user = user
      @account = user.account
    end

    def process_message(content)
      response_text = call_concierge(content)
      action, body = parse_action(response_text)

      case action
      when :confirm
        handle_confirm(body)
      when :action
        execute_action(body)
      else
        handle_respond(body)
      end
    rescue StandardError => e
      Rails.logger.error("[ConciergeService] Error: #{e.message}")
      @conversation.add_assistant_message(
        "I encountered an error processing your request. Please try again."
      )
    end

    def handle_confirmed_action(action_type, params)
      resolve_pending_action(action_type)

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

    def call_concierge(content)
      credential = find_credential
      unless credential
        return "[RESPOND] I'm unable to process your request right now — no AI provider is configured."
      end

      client = Ai::ProviderClientService.new(credential)
      messages = build_messages(content)

      result = client.send_message(messages, model: concierge_model, max_tokens: 2048, temperature: 0.3)

      if result[:success]
        extract_response_text(result[:response])
      else
        Rails.logger.warn("[ConciergeService] LLM call failed: #{result[:error]}")
        "[RESPOND] I'm having trouble processing your request right now. Please try again."
      end
    end

    def build_messages(user_content)
      messages = []
      messages << { role: "system", content: system_prompt }

      @conversation.messages.not_deleted.ordered.last(10).each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      messages << { role: "user", content: user_content }
      messages
    end

    def system_prompt
      parts = []

      parts << <<~INTRO
        You are the Powernode Assistant, an intelligent concierge for the Powernode platform.
        You help users navigate and use all platform capabilities through natural language.
      INTRO

      parts << <<~CAPABILITIES
        PLATFORM CAPABILITIES:
        - **Missions**: Create and manage development missions that automate coding workflows through 12 phases (analyze → plan → execute → test → review → deploy → merge)
        - **Teams**: Orchestrate AI agent teams for collaborative task execution
        - **Code Factory**: Automated code review and quality analysis
        - **Repositories**: Manage and analyze Git repositories
        - **Workflows**: Build and run automated AI workflows
      CAPABILITIES

      # Active missions context
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

      # Post the proposal as an assistant message with action metadata
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
        # For questions, the LLM response is already the answer
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

      # Create a temporary mission for analysis
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

      # Clean up the temporary mission
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

      Ai::AgentTeamExecutionJob.perform_later(
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
