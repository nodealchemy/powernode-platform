# frozen_string_literal: true

module Ai
  module TeamExecutionSupport
    module TaskTracking
      extend ActiveSupport::Concern

      private

      PRIORITY_MAP = { "critical" => 1, "high" => 3, "medium" => 5, "low" => 7 }.freeze

      def create_team_task(agent, description, input_data, priority: "medium")
        return nil unless defined?(Ai::TeamTask)

        numeric_priority = priority.is_a?(Integer) ? priority : PRIORITY_MAP[priority.to_s] || 5

        Ai::TeamTask.create!(
          team_execution: @execution,
          assigned_agent_id: agent.id,
          description: description.to_s.truncate(2000),
          input_data: input_data.is_a?(String) ? { task: input_data } : input_data,
          priority: numeric_priority,
          task_type: "execution",
          status: "pending"
        )
      rescue ActiveRecord::ActiveRecordError => e
        log_execution("[TaskTracking] Failed to create team task: #{e.message}")
        nil
      end

      def start_team_task!(task)
        return unless task

        task.update!(status: "in_progress", started_at: Time.current)
      end

      def complete_team_task!(task, output, tokens: 0, cost: 0.0)
        return unless task

        task.complete!(output)
        task.update!(tokens_used: tokens, cost_usd: cost) if tokens.positive? || cost.positive?
      end

      def fail_team_task!(task, reason)
        return unless task

        task.fail!(reason)
      end

      def record_team_message(message_type:, content:, from_agent: nil, to_agent: nil)
        return unless defined?(Ai::TeamMessage)

        attrs = {
          team_execution: @execution,
          message_type: message_type,
          content: content.is_a?(String) ? content : content.to_json,
          metadata: {}
        }

        # Map agents to role IDs if available
        if from_agent
          role = Ai::TeamRole.find_by(ai_agent_id: from_agent.id, agent_team_id: @team&.id)
          attrs[:from_role_id] = role&.id
          attrs[:metadata][:from_agent_name] = from_agent.name
        end

        if to_agent
          role = Ai::TeamRole.find_by(ai_agent_id: to_agent.id, agent_team_id: @team&.id)
          attrs[:to_role_id] = role&.id
          attrs[:metadata][:to_agent_name] = to_agent.name
        end

        Ai::TeamMessage.create!(attrs)
      rescue ActiveRecord::ActiveRecordError => e
        log_execution("[TaskTracking] Failed to record team message: #{e.message}")
        nil
      end

      def record_task_assignment(from_agent, to_agent, instructions)
        record_team_message(
          message_type: "task_assignment",
          content: { instructions: instructions.truncate(2000) },
          from_agent: from_agent,
          to_agent: to_agent
        )
      end

      def record_task_result(from_agent, output_summary)
        record_team_message(
          message_type: "task_result",
          content: { output_summary: output_summary.truncate(2000) },
          from_agent: from_agent
        )
      end
    end
  end
end
