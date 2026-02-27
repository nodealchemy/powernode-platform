# frozen_string_literal: true

module Ai
  class TeamConversationService
    include AgentBackedService
    attr_reader :account

    def initialize(account:)
      @account = account
    end

    # Find or create a team conversation for a given team
    def find_or_create_conversation(team, user: nil)
      conversation = team.conversations.active.order(created_at: :desc).first
      return conversation if conversation

      lead_agent = team.lead_agent
      provider = lead_agent&.provider || Ai::Provider.where(is_active: true).first

      raise "No provider available for team conversation" unless provider

      resolved_user = user ||
        team.team_executions.order(created_at: :desc).first&.triggered_by ||
        account.users.first

      Ai::Conversation.create!(
        account: account,
        user: resolved_user,
        ai_agent_id: lead_agent&.id,
        ai_provider_id: provider.id,
        conversation_type: "team",
        agent_team_id: team.id,
        title: "#{team.name} — Team Chat",
        status: "active",
        last_activity_at: Time.current
      )
    end

    # =========================================================================
    # Activity posting methods (Phase 2)
    # =========================================================================

    def post_execution_started(execution)
      return unless execution.conversation.present?

      execution.conversation.add_system_message(
        "Team execution started — #{execution.objective}",
        content_metadata: {
          "activity_type" => "execution_started",
          "execution_id" => execution.id
        }
      )
    end

    def post_task_assignment(execution, agent_name, task_description)
      return unless execution.conversation.present?

      execution.conversation.add_system_message(
        "#{agent_name} assigned: #{task_description}",
        content_metadata: {
          "activity_type" => "task_assigned",
          "agent_name" => agent_name
        }
      )
    end

    def post_task_progress(execution, agent_name, update_text)
      return unless execution.conversation.present?

      execution.conversation.add_system_message(
        "#{agent_name}: #{update_text}",
        content_metadata: {
          "activity_type" => "task_progress",
          "agent_name" => agent_name
        }
      )
    end

    def post_task_result(execution, agent_name, summary)
      return unless execution.conversation.present?

      execution.conversation.add_system_message(
        "#{agent_name} completed: #{summary}",
        content_metadata: {
          "activity_type" => "task_completed",
          "agent_name" => agent_name
        }
      )
    end

    def post_question_to_user(execution, agent_name, question)
      return unless execution.conversation.present?

      execution.conversation.add_assistant_message(
        "**#{agent_name}** asks:\n\n#{question}",
        content_metadata: {
          "actions" => [
            { "type" => "reply", "label" => "Reply", "style" => "primary" }
          ],
          "action_context" => {
            "type" => "agent_question",
            "agent_name" => agent_name,
            "execution_id" => execution.id
          }
        }
      )
    end

    def post_execution_summary(execution, summary)
      return unless execution.conversation.present?

      execution.conversation.add_assistant_message(summary)
    end

    # Post execution output as a plan message for user approval
    def post_plan_for_approval(execution)
      team = execution.agent_team
      conversation = find_or_create_conversation(team)

      plan_content = format_plan_content(execution)

      message = conversation.add_assistant_message(
        plan_content,
        message_type: "text",
        content_metadata: {
          "actions" => [
            { "type" => "approve", "label" => "Approve Plan", "style" => "primary" },
            { "type" => "request_changes", "label" => "Request Changes", "style" => "secondary" }
          ],
          "action_context" => {
            "execution_id" => execution.id,
            "team_id" => team.id,
            "team_name" => team.name,
            "status" => "pending"
          }
        }
      )

      execution.await_approval!(conversation)

      # Send notification to the user who triggered the execution
      notify_user(execution, conversation)

      # Broadcast via team execution channel
      TeamExecutionChannel.broadcast_to_team(team.id, "plan_awaiting_approval", {
        execution_id: execution.execution_id,
        conversation_id: conversation.conversation_id,
        message_id: message.message_id
      })

      conversation
    end

    # Handle a plan response (approve or request_changes)
    def handle_plan_response(conversation, action:, execution_id:, feedback: nil, current_user_id: nil)
      execution = account.ai_team_executions
                         .find_by(id: execution_id)

      raise ActiveRecord::RecordNotFound, "Execution not found" unless execution
      raise ArgumentError, "Execution is not awaiting approval" unless execution.awaiting_approval?

      case action
      when "approve"
        approve_plan(conversation, execution, current_user_id: current_user_id)
      when "request_changes"
        request_changes(conversation, execution, feedback, current_user_id: current_user_id)
      else
        raise ArgumentError, "Invalid action: #{action}. Must be 'approve' or 'request_changes'"
      end
    end

    # Classify user intent from a natural language reply in a team conversation
    def classify_user_intent(conversation, message_content)
      # Find the most recent pending plan message
      pending_message = find_pending_plan_message(conversation)
      return nil unless pending_message

      intent = classify_intent_with_llm_fallback(message_content)

      if intent == :approve
        execution_id = pending_message.content_metadata.dig("action_context", "execution_id")
        handle_plan_response(conversation, action: "approve", execution_id: execution_id,
                             current_user_id: conversation.user_id)
        :approve
      elsif intent == :request_changes
        execution_id = pending_message.content_metadata.dig("action_context", "execution_id")
        handle_plan_response(conversation, action: "request_changes", execution_id: execution_id,
                             feedback: message_content, current_user_id: conversation.user_id)
        :request_changes
      else
        :discussion
      end
    end

    private

    def approve_plan(conversation, execution, current_user_id: nil)
      # Update the plan message action_context
      update_plan_message_status(conversation, execution.id, "approved")

      # Record audit fields
      audit_attrs = { approval_decision: "approved", approval_decided_at: Time.current }
      audit_attrs[:approval_decided_by_id] = current_user_id if current_user_id.present?
      execution.update!(audit_attrs)

      # Mark execution completed
      execution.complete!(execution.output_result || {})

      # Dispatch follow-up execution with approved plan to worker
      WorkerJobService.enqueue_ai_team_execution(
        team_id: execution.agent_team_id,
        user_id: execution.triggered_by_id,
        input: {
          plan_approval: true,
          approved_plan: execution.output_result,
          task: execution.objective
        },
        context: { parent_execution_id: execution.id }
      )

      # Post confirmation message
      conversation.add_system_message("Plan approved. Starting execution...")
    end

    def request_changes(conversation, execution, feedback, current_user_id: nil)
      # Update the plan message action_context
      update_plan_message_status(conversation, execution.id, "changes_requested")

      # Record audit fields
      audit_attrs = { approval_decision: "changes_requested", approval_decided_at: Time.current,
                      approval_feedback: feedback }
      audit_attrs[:approval_decided_by_id] = current_user_id if current_user_id.present?
      execution.update!(audit_attrs)

      # Mark execution completed (the revision will be a new execution)
      execution.complete!(execution.output_result || {})

      # Dispatch revision execution to worker
      WorkerJobService.enqueue_ai_team_execution(
        team_id: execution.agent_team_id,
        user_id: execution.triggered_by_id,
        input: {
          revision_requested: true,
          user_feedback: feedback,
          previous_plan: execution.output_result,
          task: execution.objective
        },
        context: { parent_execution_id: execution.id }
      )

      # Post confirmation message
      conversation.add_system_message("Changes requested. Revising plan...")
    end

    # =========================================================================
    # LLM-based intent classification (Phase 6)
    # =========================================================================

    def classify_intent_with_llm_fallback(message_content)
      classify_intent_via_llm(message_content)
    rescue StandardError => e
      Rails.logger.debug("[TeamConversationService] LLM classification failed, using heuristic: #{e.message}")
      classify_intent_via_heuristic(message_content)
    end

    def classify_intent_via_llm(message_content)
      agent = discover_service_agent(
        "Classify user message intent for conversation routing such as approve, change, or discussion",
        fallback_slug: "intent-classifier"
      )
      return classify_intent_via_heuristic(message_content) unless agent

      client = build_agent_client(agent)
      messages = [
        { role: "system", content: "Classify the user's message as one of: approve, change, discussion. Respond with ONLY one word." },
        { role: "user", content: message_content.to_s.truncate(500) }
      ]

      model = agent_model(agent)
      response = client.complete(messages: messages, model: model, max_tokens: agent_max_tokens(agent), temperature: agent_temperature(agent))

      unless response.success?
        return classify_intent_via_heuristic(message_content)
      end

      response_text = response.content.to_s.strip.downcase
      case response_text
      when /\bapprove\b/ then :approve
      when /\bchange\b/ then :request_changes
      else :discussion
      end
    end

    # =========================================================================
    # Heuristic classification (original)
    # =========================================================================

    def classify_intent_via_heuristic(message_content)
      text = message_content.to_s.strip.downcase

      approve_patterns = [
        /\b(approv|lgtm|looks?\s+good|go\s+ahead|proceed|accept|ship\s+it|confirm|yes|approved)\b/
      ]

      change_patterns = [
        /\b(change|revis|modif|updat|fix|redo|rework|adjust|rethink|reconsider|wrong|incorrect|missing)\b/
      ]

      approve_score = approve_patterns.count { |p| text.match?(p) }
      change_score = change_patterns.count { |p| text.match?(p) }

      if approve_score > change_score && approve_score > 0
        :approve
      elsif change_score > approve_score && change_score > 0
        :request_changes
      else
        :discussion
      end
    end

    # =========================================================================
    # Helpers
    # =========================================================================

    def format_plan_content(execution)
      output = execution.output_result
      team = execution.agent_team

      header = "## Plan Ready for Review\n\n"
      header += "> **This plan requires your approval before execution proceeds.**\n\n"
      header += "**Team**: #{team.name}\n"
      header += "**Objective**: #{execution.objective}\n\n"

      body = if output.is_a?(Hash)
               format_hash_output(output)
             else
               output.to_s
             end

      "#{header}---\n\n#{body}"
    end

    def format_hash_output(output)
      # Try to extract meaningful content from the output
      if output["synthesized_output"].present?
        output["synthesized_output"].to_s
      elsif output["response"].present?
        output["response"].to_s
      elsif output["results"].is_a?(Array)
        output["results"].map { |r|
          "### #{r['agent'] || r[:agent]}\n#{r['output']&.dig('response') || r[:output]&.dig(:response) || r['output'].to_s}"
        }.join("\n\n")
      else
        output.to_json
      end
    end

    def find_pending_plan_message(conversation)
      conversation.messages
                  .where(role: "assistant")
                  .order(created_at: :desc)
                  .find { |m|
                    m.content_metadata.dig("action_context", "status") == "pending"
                  }
    end

    def update_plan_message_status(conversation, execution_id, new_status)
      message = conversation.messages
                            .where(role: "assistant")
                            .order(created_at: :desc)
                            .find { |m|
                              m.content_metadata.dig("action_context", "execution_id") == execution_id
                            }

      return unless message

      updated_metadata = message.content_metadata.deep_dup
      updated_metadata["action_context"]["status"] = new_status
      updated_metadata["action_context"]["resolved_at"] = Time.current.iso8601
      message.update!(content_metadata: updated_metadata)

      # Broadcast message update
      broadcast_message_updated(conversation, message)
    end

    def broadcast_message_updated(conversation, message)
      return unless conversation.websocket_channel.present?

      AiConversationChannel.broadcast_message_updated(conversation, message)
    end

    def notify_user(execution, conversation)
      user = execution.triggered_by
      return unless user

      lead_agent = execution.agent_team.lead_agent

      Notification.create_for_user(
        user,
        type: "ai_plan_review",
        title: "Plan Ready for Review",
        message: "#{execution.agent_team.name} has produced a plan for \"#{execution.objective&.truncate(80)}\". Review and approve to proceed.",
        severity: "info",
        action_label: "Review Plan",
        category: "ai",
        metadata: {
          agent_id: lead_agent&.id,
          agent_name: lead_agent&.name || execution.agent_team.name,
          conversation_id: conversation.id
        }
      )
    rescue StandardError => e
      Rails.logger.warn("[TeamConversationService] Failed to create notification: #{e.message}")
    end
  end
end
