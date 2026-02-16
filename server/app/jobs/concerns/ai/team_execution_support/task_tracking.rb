# frozen_string_literal: true

module Ai
  module TeamExecutionSupport
    module TaskTracking
      extend ActiveSupport::Concern

      private

      def create_team_task(agent, description, input_data, priority: "medium")
        return nil unless defined?(Ai::TeamTask)

        Ai::TeamTask.create!(
          team_execution: @execution,
          agent: agent,
          description: description,
          input_data: input_data,
          priority: priority,
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

        task.update!(
          status: "completed",
          output_data: output,
          tokens_used: tokens,
          cost_usd: cost,
          completed_at: Time.current
        )
      end

      def fail_team_task!(task, reason)
        return unless task

        task.update!(
          status: "failed",
          error_message: reason,
          completed_at: Time.current
        )
      end

      def record_team_message(message_type:, content:, from_agent: nil, to_agent: nil)
        return unless defined?(Ai::TeamMessage)

        Ai::TeamMessage.create!(
          team_execution: @execution,
          message_type: message_type,
          content: content.is_a?(String) ? content : content.to_json,
          from_agent: from_agent,
          to_agent: to_agent,
          timestamp: Time.current
        )
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
