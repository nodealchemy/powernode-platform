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
    # @param severity [String] info, warning, error — the NOTIFICATION severity,
    #   stored on the record and rendered by the UI.
    # @param priority [Integer] 0 (normal) to 3 (critical)
    # @param action_url [String, nil] optional action link
    # @param policy_severity [String, nil] the POLICY severity
    #   (Ai::InterventionPolicyService's vocabulary: info / warning / critical).
    #   Pass "critical" to DECLARE that this is a critical event. Defaults to
    #   nil, which resolves as non-critical — `severity` is NEVER read as a
    #   policy severity. See the note above #notify_escalation.
    # @return [Hash] { delivered: Boolean, channel: String, policy_result: Hash }
    def notify(user:, type:, title:, message:, severity: "info", priority: 0, action_url: nil,
               policy_severity: nil)
      # Check intervention policy
      policy_service = InterventionPolicyService.new(account: account)
      policy_result = policy_service.resolve(
        action_category: "status_update",
        agent: agent,
        user: user,
        severity: policy_severity
      )

      case policy_result[:policy]
      when "block"
        return { delivered: false, channel: nil, policy_result: policy_result, reason: "blocked_by_policy" }
      when "silent"
        return { delivered: false, channel: nil, policy_result: policy_result, reason: "silent_policy" }
      end

      # The account's daily notification budget is spent (IMP-73dff8186c1e).
      # Resolution keeps a real authorisation verb so gated WRITES elsewhere are
      # parked rather than refused, and reports the delivery half separately —
      # this path is the one that must honour it. Do NOT infer suppression from
      # `channels`: it arrives empty, and `[].presence` is nil, so the fallback
      # below would deliver the notification the cap exists to withhold.
      if policy_result[:notifications_suppressed]
        return { delivered: false, channel: nil, policy_result: policy_result,
                 reason: "notification_limit_reached" }
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

    # Notify all relevant users for an escalation.
    #
    # CRITICALITY IS DECLARED, NOT INFERRED (IMP-34beef811fdf). Two severity
    # vocabularies meet in #notify:
    #
    #   Notification    — info / success / warning / error / critical
    #   policy severity — info / warning / critical
    #                     (Ai::InterventionPolicyService#resolve)
    #
    # A critical escalation is RENDERED as the notification severity "error",
    # and that rendering is not a mistake to be undone: the frontend's
    # NotificationSeverity union is info/success/warning/error and unmapped
    # values fall back to the INFO icon, so storing a literal "critical" would
    # render the most urgent event as the least urgent one.
    #
    # But forwarding that rendered word as the POLICY severity left resolution
    # unable to see criticality at all — a critical escalation arrived there as
    # "error", so both of resolve's critical branches (the silent-verb override
    # and the notification-cap exemption) were dead for every caller here.
    #
    # `policy_severity` carries the fact explicitly instead, and #notify reads
    # ONLY that — the notification `severity` is never re-read as a policy
    # severity. Do NOT reintroduce either half of that (no severity map, no
    # `policy_severity || severity` fallback). A rendered word means critical
    # only where a caller WROTE it to mean that, and
    # Ai::Tools::AgentAutonomyTool#send_proactive_notification forwards an
    # agent's own `params["severity"]` verbatim with no enum enforcement
    # (Ai::Tools::BaseTool#validate_params! checks required-ness only). Either
    # shortcut would let the very agent an operator is capping exempt itself
    # from both the daily notification budget and a `silent` policy just by
    # labelling its routine traffic "error" — or "critical".
    #
    # WHERE THE TRUST BOUNDARY ACTUALLY SITS, since criticality is necessarily
    # agent-supplied here: escalations and issue reports ARE agent-declared,
    # and honouring them is the entire point — the escalation this method
    # notifies about is raised by an agent through Ai::EscalationService. What
    # separates them from chatter is not who chose the word but what the action
    # is: #notify_escalation and Ai::Tools::AgentAutonomyTool#report_issue are
    # incident-routing actions that also write a durable, auditable row
    # (Ai::AgentEscalation / Ai::AgentObservation) and exist to reach a human,
    # so an operator can review what the agent called critical and why.
    # #send_proactive_notification is unstructured chatter that leaves no such
    # record, so it gets no elevation. An operator who wants to bound a noisy
    # agent's incident channel too has the real lever for it — a `block` or
    # `silent` row, which outranks this exemption — rather than a volume
    # budget, which by contract only reduces routine chatter.
    def notify_escalation(escalation:)
      target_user = escalation.escalated_to_user
      return unless target_user

      critical = escalation.severity == "critical"

      notify(
        user: target_user,
        type: "agent_escalation",
        title: "Escalation: #{escalation.title}",
        message: "**#{agent.name}** needs help with an escalation.\n\n" \
                 "**Severity:** #{escalation.severity}\n\n" \
                 "#{escalation.title}",
        severity: critical ? "error" : "warning",
        priority: critical ? 3 : 1,
        action_url: "/ai/escalations/#{escalation.id}",
        policy_severity: critical ? "critical" : nil
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
        message: "**#{agent.name}** has submitted a proposal.\n\n" \
                 "**Priority:** #{proposal.priority}\n" \
                 "**Type:** #{proposal.proposal_type.titleize}",
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
        category: "ai",
        action_url: action_url,
        metadata: { agent_id: agent.id, agent_name: agent.name, priority: priority }
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
        # participants is a jsonb array of user ids on ai_conversations (no join table)
        .where("participants @> ?", [ user.id ].to_json)
        .first
    rescue StandardError => e
      Rails.logger.warn("[AgentOutreach] Failed to find conversation: #{e.message}")
      nil
    end
  end
end
