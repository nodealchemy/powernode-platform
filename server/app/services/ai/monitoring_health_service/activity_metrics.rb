# frozen_string_literal: true

module Ai
  class MonitoringHealthService
    module ActivityMetrics
      extend ActiveSupport::Concern

      def recent_activity_summary
        {
          last_hour: activity_for_period(1.hour.ago),
          last_24h: activity_for_period(24.hours.ago)
        }
      end

      def recent_error_analysis
        failed_runs = ::Ai::WorkflowRun.where("created_at >= ? AND status = ?", 24.hours.ago, "failed")
                                     .includes(:workflow)
                                     .limit(10)

        {
          total_failures: failed_runs.count,
          recent_failures: failed_runs.map do |run|
            {
              workflow_name: run.workflow.name,
              failed_at: run.completed_at,
              error_summary: run.error_details.is_a?(Hash) ? run.error_details["error_message"] : "Unknown error"
            }
          end
        }
      end

      def performance_metrics
        {
          average_execution_time: calculate_average_execution_time,
          throughput: {
            workflows_per_hour: ::Ai::WorkflowRun.where("created_at >= ?", 1.hour.ago).count,
            conversations_per_hour: ::Ai::Conversation.where("created_at >= ?", 1.hour.ago).count
          },
          resource_usage: {
            active_conversations: ::Ai::Conversation.where("updated_at >= ?", 1.hour.ago).count,
            running_workflows: ::Ai::WorkflowRun.where(status: %w[initializing running waiting_approval]).count,
            database_connections: ActiveRecord::Base.connection_pool.connections.size
          }
        }
      end

      def resource_metrics
        pool_stat = ActiveRecord::Base.connection_pool.stat
        {
          database: {
            connections: pool_stat[:connections],
            available: pool_stat[:idle]
          },
          redis: check_redis_health,
          active_records: {
            active_workflows: ::Ai::WorkflowRun.where(status: %w[initializing running waiting_approval]).count,
            active_conversations: ::Ai::Conversation.where("updated_at >= ?", 1.hour.ago).count
          }
        }
      end

      private

      def activity_for_period(since)
        {
          workflow_runs: ::Ai::WorkflowRun.where("created_at >= ?", since).count,
          completed_runs: ::Ai::WorkflowRun.where("created_at >= ? AND status = ?", since, "completed").count,
          failed_runs: ::Ai::WorkflowRun.where("created_at >= ? AND status = ?", since, "failed").count
        }
      end

      def calculate_average_execution_time
        completed_runs = ::Ai::WorkflowRun.where(status: "completed")
                                        .where("completed_at >= ?", 24.hours.ago)
                                        .where.not(duration_ms: nil)

        return 0 if completed_runs.empty?

        (completed_runs.average(:duration_ms) || 0).round(2)
      end
    end
  end
end
