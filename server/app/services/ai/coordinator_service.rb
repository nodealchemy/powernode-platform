# frozen_string_literal: true

module Ai
  class CoordinatorService
    def initialize(conversation:, user:)
      @conversation = conversation
      @team = conversation.agent_team
      @coordinator = @team.lead_agent
      @user = user
    end

    def process_message(content)
      response_text = call_coordinator(content)
      action, body = parse_action(response_text)

      case action
      when :delegate
        handle_delegate(body, content)
      when :clarify
        handle_clarify(body)
      else
        handle_respond(body)
      end
    rescue StandardError => e
      Rails.logger.error("[CoordinatorService] Error processing message: #{e.message}")
      @conversation.add_assistant_message(
        "I encountered an error processing your request. Please try again."
      )
    end

    private

    def call_coordinator(content)
      unless @coordinator&.provider&.is_active?
        Rails.logger.warn("[CoordinatorService] Coordinator agent has no active provider")
        return "[RESPOND] I'm unable to process your request right now — no provider credentials are configured."
      end

      client = WorkerLlmClient.new(agent_id: @coordinator.id)
      messages = build_messages(content)

      response = client.complete(messages: messages, model: coordinator_model || @coordinator.provider.default_model, max_tokens: 2048, temperature: 0.3)

      if response.success?
        response.content
      else
        Rails.logger.warn("[CoordinatorService] LLM call failed")
        "[RESPOND] I'm unable to process your request right now. Please try again later."
      end
    end

    def build_messages(user_content)
      messages = []
      messages << { role: "system", content: system_prompt }

      # Include last 10 conversation messages for context
      @conversation.messages.not_deleted.ordered.last(10).each do |msg|
        messages << { role: msg.role, content: msg.content }
      end

      messages << { role: "user", content: user_content }
      messages
    end

    def system_prompt
      parts = []

      # Read base prompt from the coordinator agent's DB record (editable via agents API)
      base_prompt = @coordinator&.build_system_prompt_with_profile.presence
      if base_prompt
        parts << base_prompt
      else
        parts << "You are the coordinator for the \"#{@team.name}\" team."
        parts << "Description: #{@team.description}" if @team.description.present?
      end

      # Dynamic team member listing (live DB query — stays in code)
      members = @team.members.includes(:agent)
      if members.any?
        member_lines = members.map do |m|
          "- #{m.agent.name} (#{m.role}): #{m.agent.system_prompt&.truncate(150)}"
        end
        parts << "Team members:\n#{member_lines.join("\n")}"
      end

      # Action-grammar markers (coupled to parse_action — stays in code)
      parts << <<~INSTRUCTIONS
        Based on the user's message, choose ONE action by starting your response with the appropriate marker:

        [RESPOND] message — Reply directly to the user when you can answer without the team.
        [DELEGATE] objective — Start a team execution when the request requires team collaboration.
        [CLARIFY] question — Ask the user a clarifying question before proceeding.

        Always start your response with exactly one of these markers followed by your message.
      INSTRUCTIONS

      parts.join("\n\n")
    end

    def parse_action(response_text)
      text = response_text.to_s.strip

      if text.start_with?("[DELEGATE]")
        [:delegate, text.sub("[DELEGATE]", "").strip]
      elsif text.start_with?("[CLARIFY]")
        [:clarify, text.sub("[CLARIFY]", "").strip]
      elsif text.start_with?("[RESPOND]")
        [:respond, text.sub("[RESPOND]", "").strip]
      else
        # Default to respond if no marker found
        [:respond, text]
      end
    end

    def handle_respond(message)
      @conversation.add_assistant_message(message)
    end

    def handle_delegate(objective, original_content)
      @conversation.add_system_message("Delegating to team: #{objective.truncate(200)}")

      WorkerJobService.enqueue_ai_team_execution(
        team_id: @team.id,
        user_id: @user.id,
        input: { task: objective, original_message: original_content },
        context: { conversation_id: @conversation.id, source: "coordinator" }
      )
    end

    def handle_clarify(question)
      @conversation.add_assistant_message(question)
    end

    def coordinator_model
      @coordinator&.model || @coordinator&.mcp_tool_manifest&.dig("model")
    end

  end
end
