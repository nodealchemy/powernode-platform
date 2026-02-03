# frozen_string_literal: true

module Ai
  class WorkflowRun
    module ProgressTracking
      extend ActiveSupport::Concern

      def progress_percentage
        return 0 if total_nodes == 0
        return 100 if completed?

        (completed_nodes.to_f / total_nodes * 100).round(2)
      end

      def execution_progress
        {
          percentage: progress_percentage,
          completed_nodes: completed_nodes,
          failed_nodes: failed_nodes,
          pending_nodes: total_nodes - completed_nodes - failed_nodes,
          total_nodes: total_nodes,
          current_status: status
        }
      end

      def update_progress!
        progress_key = "updating_workflow_progress_#{id}"

        return if Thread.current[progress_key]

        Thread.current[progress_key] = true

        begin
          # Use with_lock to prevent race conditions during progress updates
          with_lock do
            executions = node_executions

            new_completed = executions.where(status: %w[completed skipped]).count
            new_failed = executions.where(status: "failed").count

            if completed_nodes != new_completed || failed_nodes != new_failed
              # Use update_columns for atomic update without callbacks
              update_columns(
                completed_nodes: new_completed,
                failed_nodes: new_failed
              )
            end
          end
        ensure
          Thread.current[progress_key] = nil
        end
      end

      def execution_duration
        return nil unless started_at

        end_time = completed_at || cancelled_at || Time.current
        end_time - started_at
      end

      def execution_duration_seconds
        execution_duration&.to_i
      end

      def execution_time_ms
        return duration_ms if duration_ms.present?
        return nil unless execution_duration

        (execution_duration * 1000).to_i
      end

      alias_method :execution_duration_ms, :execution_time_ms

      def time_since_start
        return nil unless started_at

        Time.current - started_at
      end

      def estimated_completion_time
        return nil unless running? && started_at && total_nodes > 0 && completed_nodes > 0

        avg_time_per_node = time_since_start / completed_nodes
        remaining_nodes = total_nodes - completed_nodes

        Time.current + (avg_time_per_node * remaining_nodes)
      end

      def calculate_execution_metrics
        executions = node_executions

        {
          total_nodes: workflow.workflow_nodes.count,
          completed_nodes: executions.where(status: "completed").count,
          failed_nodes: executions.where(status: "failed").count,
          running_nodes: executions.where(status: "running").count,
          duration_ms: duration_ms || 0,
          total_cost: total_cost || 0,
          status: status
        }
      end
    end
  end
end
