# frozen_string_literal: true

module Ai
  class EscalationService
    attr_reader :account

    def initialize(account:)
      @account = account
    end

    # Create an escalation from an agent
    def escalate(agent:, title:, escalation_type:, severity: "medium", context: {})
      chain = build_escalation_chain(agent)
      first_user = chain.first

      escalation = account.ai_agent_escalations.create!(
        ai_agent_id: agent.id,
        title: title,
        escalation_type: escalation_type,
        severity: severity,
        context: context,
        escalation_chain: chain,
        escalated_to_user_id: first_user&.dig("user_id")
      )

      # Notify the first person in the chain
      outreach = AgentOutreachService.new(account: account, agent: agent)
      outreach.notify_escalation(escalation: escalation)

      escalation
    end

    # Auto-escalate overdue escalations to the next level
    def auto_escalate_overdue!
      count = 0

      Ai::AgentEscalation
        .where(account_id: account.id)
        .overdue
        .find_each do |escalation|
          escalation.escalate_to_next_level!

          # Notify the new target
          if escalation.escalated_to_user
            agent = escalation.agent
            outreach = AgentOutreachService.new(account: account, agent: agent)
            outreach.notify_escalation(escalation: escalation)
          end

          count += 1
        rescue StandardError => e
          Rails.logger.error "[EscalationService] Failed to auto-escalate #{escalation.id}: #{e.message}"
        end

      count
    end

    # Resolve an escalation
    def resolve(escalation:, status: "resolved")
      escalation.resolve!(status: status)
    end

    private

    # Build escalation chain: recent interacting user → users with ai.escalations.resolve → account admins
    def build_escalation_chain(agent)
      chain = []

      # 1. Most recent user who interacted with this agent
      recent_user_id = Ai::Conversation
        .where(account_id: account.id, ai_agent_id: agent.id)
        .joins(:participants)
        .order(updated_at: :desc)
        .limit(1)
        .pluck("ai_conversation_participants.user_id")
        .first

      if recent_user_id
        user = User.find_by(id: recent_user_id)
        chain << { "user_id" => user.id, "role" => "recent_interactor" } if user
      end

      # 2. Users with ai.escalations.resolve permission
      resolver_ids = User.joins(user_roles: { role: :permissions })
        .where(account_id: account.id)
        .where(permissions: { name: "ai.escalations.resolve" })
        .where.not(id: chain.map { |c| c["user_id"] })
        .distinct
        .pluck(:id)

      resolver_ids.each do |uid|
        chain << { "user_id" => uid, "role" => "escalation_resolver" }
      end

      # 3. Account admins as fallback
      admin_ids = User.joins(user_roles: :role)
        .where(account_id: account.id)
        .where(roles: { name: %w[owner account.owner admin] })
        .where.not(id: chain.map { |c| c["user_id"] })
        .distinct
        .pluck(:id)

      admin_ids.each do |uid|
        chain << { "user_id" => uid, "role" => "account_admin" }
      end

      chain
    end
  end
end
