# frozen_string_literal: true

module Ai
  module Analytics
    # Service for AI performance analysis
    #
    # Provides detailed performance analysis including:
    # - Response time analysis
    # - Success rate analysis
    # - Throughput analysis
    # - Error rate analysis
    # - Bottleneck identification
    #
    # Usage:
    #   service = Ai::Analytics::PerformanceAnalysisService.new(account: current_account, time_range: 30.days)
    #   analysis = service.full_analysis
    #
    class PerformanceAnalysisService
      include ResponseTimeAnalysis
      include ThroughputAndErrors
      include BottleneckIdentification

      attr_reader :account, :time_range

      def initialize(account:, time_range: 30.days)
        @account = account
        @time_range = time_range
      end

      # Generate full performance analysis
      # @return [Hash] Complete performance analysis
      def full_analysis
        {
          response_times: analyze_response_times,
          success_rates: analyze_success_rates,
          throughput: analyze_throughput,
          error_rates: analyze_error_rates,
          resource_utilization: analyze_resource_utilization,
          bottlenecks: identify_bottlenecks,
          sla_compliance: analyze_sla_compliance,
          performance_trends: analyze_performance_trends
        }
      end

      private

      def workflow_runs
        ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: account.id })
      end

      def completed_runs
        workflow_runs.where(status: "completed")
      end

      def node_executions
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow).where(ai_workflows: { account_id: account.id })
      end
    end
  end
end
