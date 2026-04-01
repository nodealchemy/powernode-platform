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
        failed_executions = ::Ai::AgentExecution.where("created_at >= ? AND status = ?", 24.hours.ago, "failed")
                                               .includes(:agent)
                                               .limit(10)

        {
          total_failures: failed_executions.count,
          recent_failures: failed_executions.map do |execution|
            {
              agent_name: execution.agent.name,
              failed_at: execution.completed_at,
              error_summary: execution.error_details.is_a?(Hash) ? execution.error_details["error_message"] : "Unknown error"
            }
          end
        }
      end

      def performance_metrics
        {
          average_execution_time: calculate_average_execution_time,
          throughput: {
            executions_per_hour: ::Ai::AgentExecution.where("created_at >= ?", 1.hour.ago).count,
            conversations_per_hour: ::Ai::Conversation.where("created_at >= ?", 1.hour.ago).count
          },
          resource_usage: {
            active_conversations: ::Ai::Conversation.where("updated_at >= ?", 1.hour.ago).count,
            running_executions: ::Ai::AgentExecution.where(status: "running").count,
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
            active_executions: ::Ai::AgentExecution.where(status: "running").count,
            active_conversations: ::Ai::Conversation.where("updated_at >= ?", 1.hour.ago).count
          }
        }
      end

      private

      def activity_for_period(since)
        {
          agent_executions: ::Ai::AgentExecution.where("created_at >= ?", since).count,
          completed_executions: ::Ai::AgentExecution.where("created_at >= ? AND status = ?", since, "completed").count,
          failed_executions: ::Ai::AgentExecution.where("created_at >= ? AND status = ?", since, "failed").count
        }
      end

      def calculate_average_execution_time
        completed_executions = ::Ai::AgentExecution.where(status: "completed")
                                                   .where("completed_at >= ?", 24.hours.ago)
                                                   .where.not(duration_ms: nil)

        return 0 if completed_executions.empty?

        (completed_executions.average(:duration_ms) || 0).round(2)
      end
    end
  end
end
