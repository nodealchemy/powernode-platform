# frozen_string_literal: true

module Ai
  class AgentOutreachService
    AGENT_NOTIFICATION_TYPES = %w[
      agent_proposal agent_escalation agent_status_update
      agent_issue_detected agent_feedback_request
      agent_goal_achieved agent_improvement_applied
    ].freeze

    attr_reader :account, :agent

    def initialize(account:, agent:)
      @account = account
      @agent = agent
    end

    # Send a notification to a user, respecting intervention policies.
    #
    # @param user [User] recipient
    # @param type [String] notification type from AGENT_NOTIFICATION_TYPES
    # @param title [String] notification title
    # @param message [String] notification body
    # @param severity [String] info, warning, error
    # @param priority [Integer] 0 (normal) to 3 (critical)
    # @param action_url [String, nil] optional action link
    # @return [Hash] { delivered: Boolean, channel: String, policy_result: Hash }
    def notify(user:, type:, title:, message:, severity: "info", priority: 0, action_url: nil)
      # Check intervention policy
      policy_service = InterventionPolicyService.new(account: account)
      policy_result = policy_service.resolve(
        action_category: "status_update",
        agent: agent,
        user: user,
        severity: severity
      )

      case policy_result[:policy]
      when "block"
        return { delivered: false, channel: nil, policy_result: policy_result, reason: "blocked_by_policy" }
      when "silent"
        return { delivered: false, channel: nil, policy_result: policy_result, reason: "silent_policy" }
      end

      # Deliver through preferred channels
      channels = policy_result[:channels].presence || %w[notification]
      delivered_via = nil

      channels.each do |channel|
        case channel
        when "notification"
          deliver_notification(user, type: type, title: title, message: message,
                              severity: severity, priority: priority, action_url: action_url)
          delivered_via = "notification"
          break
        when "workspace"
          deliver_workspace_message(user, title: title, message: message)
          delivered_via = "workspace"
          break
        end
      end

      { delivered: delivered_via.present?, channel: delivered_via, policy_result: policy_result }
    end

    # Notify all relevant users for an escalation
    def notify_escalation(escalation:)
      target_user = escalation.escalated_to_user
      return unless target_user

      notify(
        user: target_user,
        type: "agent_escalation",
        title: "Escalation: #{escalation.title}",
        message: "Agent #{agent.name} needs help: #{escalation.title} (#{escalation.severity})",
        severity: escalation.severity == "critical" ? "error" : "warning",
        priority: escalation.severity == "critical" ? 3 : 1,
        action_url: "/ai/escalations/#{escalation.id}"
      )
    end

    # Notify target user about a new proposal
    def notify_proposal(proposal:)
      target_user = proposal.target_user
      return unless target_user

      notify(
        user: target_user,
        type: "agent_proposal",
        title: "Proposal: #{proposal.title}",
        message: "Agent #{agent.name} proposes: #{proposal.title} (#{proposal.priority} priority)",
        severity: proposal.priority == "critical" ? "warning" : "info",
        priority: proposal.priority == "critical" ? 2 : 0,
        action_url: "/ai/proposals/#{proposal.id}"
      )
    end

    private

    def deliver_notification(user, type:, title:, message:, severity:, priority:, action_url:)
      Notification.create_for_user(
        user,
        type: type,
        title: title,
        message: message,
        severity: severity,
        priority: priority,
        category: "ai",
        action_url: action_url,
        metadata: { agent_id: agent.id, agent_name: agent.name }
      )
    end

    def deliver_workspace_message(user, title:, message:)
      # Find or create a conversation between this agent and the user
      conversation = find_or_create_agent_conversation(user)
      return unless conversation

      conversation.messages.create!(
        account_id: account.id,
        role: "assistant",
        content: "**#{title}**\n\n#{message}",
        ai_agent_id: agent.id,
        content_metadata: {
          activity_type: "agent_outreach",
          agent_id: agent.id,
          agent_name: agent.name
        }
      )
    rescue StandardError => e
      Rails.logger.warn("[AgentOutreach] Failed to deliver workspace message: #{e.message}")
    end

    def find_or_create_agent_conversation(user)
      # Look for existing direct conversation
      Ai::Conversation
        .where(account_id: account.id, ai_agent_id: agent.id)
        .where(conversation_type: "direct")
        .joins(:participants)
        .where(ai_conversation_participants: { user_id: user.id })
        .first
    rescue StandardError => e
      Rails.logger.warn("[AgentOutreach] Failed to find conversation: #{e.message}")
      nil
    end
  end
end
