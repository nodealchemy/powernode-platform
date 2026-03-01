# frozen_string_literal: true

module Ai
  module Autonomy
    module Sensors
      class WorkspaceActivitySensor < Base
        def sensor_type
          "workspace"
        end

        def collect
          observations = []

          # Check for unanswered messages in agent's conversations
          unanswered = unanswered_messages
          if unanswered > 0
            obs = build_observation(
              title: "#{unanswered} unanswered messages in workspace conversations",
              observation_type: "request",
              severity: unanswered > 5 ? "warning" : "info",
              data: { unanswered_count: unanswered },
              requires_action: true,
              expires_in: 4.hours
            )
            observations << obs if obs
          end

          # Check for pending approval requests
          pending_approvals = pending_approval_count
          if pending_approvals > 0
            obs = build_observation(
              title: "#{pending_approvals} pending approval requests",
              observation_type: "request",
              severity: pending_approvals > 3 ? "warning" : "info",
              data: { pending_count: pending_approvals },
              requires_action: true,
              expires_in: 2.hours
            )
            observations << obs if obs
          end

          observations.compact
        end

        private

        def unanswered_messages
          Ai::Conversation
            .where(account_id: account.id, ai_agent_id: agent.id)
            .joins(:messages)
            .where(ai_messages: { role: "user" })
            .where("ai_messages.created_at >= ?", 24.hours.ago)
            .where.not(
              id: Ai::Conversation
                .where(account_id: account.id, ai_agent_id: agent.id)
                .joins(:messages)
                .where(ai_messages: { role: "assistant" })
                .where("ai_messages.created_at >= ?", 24.hours.ago)
                .select(:id)
            )
            .distinct
            .count
        rescue StandardError
          0
        end

        def pending_approval_count
          Ai::MissionApproval
            .where(account_id: account.id, status: "pending")
            .where("created_at >= ?", 48.hours.ago)
            .count
        rescue StandardError
          0
        end
      end
    end
  end
end
