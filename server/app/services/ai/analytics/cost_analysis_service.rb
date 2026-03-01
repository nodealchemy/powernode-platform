# frozen_string_literal: true

module Ai
  module Analytics
    # Service for AI cost analysis, optimization insights, and ROI tracking
    #
    # Provides detailed cost analysis including:
    # - Cost breakdown by provider, agent, workflow
    # - Cost trends and forecasting
    # - Budget tracking and alerts
    # - Optimization recommendations
    # - ROI calculations by workflow, agent, and provider
    # - ROI projections and recommendations
    #
    # Usage:
    #   service = Ai::Analytics::CostAnalysisService.new(account: current_account, time_range: 30.days)
    #   analysis = service.full_analysis
    #   roi_data = service.roi_dashboard
    #
    class CostAnalysisService
      include Breakdown
      include BudgetAndForecasting
      include RoiAnalytics

      attr_reader :account, :time_range, :hourly_rate

      # Default hourly rate for time savings calculations
      DEFAULT_HOURLY_RATE = 75.0

      # Average time saved per automated task (in hours)
      DEFAULT_TIME_SAVED_PER_TASK = 0.25

      def initialize(account:, time_range: 30.days, hourly_rate: DEFAULT_HOURLY_RATE)
        @account = account
        @time_range = time_range
        @hourly_rate = hourly_rate
      end

      # Generate full cost analysis
      # @return [Hash] Complete cost analysis
      def full_analysis
        {
          total_cost: calculate_total_cost,
          cost_trend: calculate_cost_trend,
          cost_by_provider: cost_breakdown_by_provider,
          cost_by_agent: cost_breakdown_by_agent,
          cost_by_workflow: cost_breakdown_by_workflow,
          cost_by_model: cost_breakdown_by_model,
          daily_costs: daily_cost_breakdown,
          budget_status: budget_analysis,
          optimization_potential: estimate_cost_savings,
          budget_forecast: generate_budget_forecast,
          anomalies: detect_cost_anomalies
        }
      end

      # Calculate total cost for time range
      # @return [Hash] Total cost with breakdown
      def calculate_total_cost
        start_time = time_range.ago

        workflow_cost = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time).sum(:total_cost).to_f
        node_cost = node_executions.where("ai_workflow_node_executions.created_at >= ?", start_time).sum(:cost).to_f

        {
          total: workflow_cost.round(6),
          workflow_cost: workflow_cost.round(6),
          node_cost: node_cost.round(6),
          currency: "USD",
          period_start: start_time.iso8601,
          period_end: Time.current.iso8601
        }
      end

      # Calculate cost trend (change from previous period)
      # @return [Hash] Cost trend data
      def calculate_cost_trend
        start_time = time_range.ago
        previous_start = start_time - time_range

        current_cost = workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time).sum(:total_cost).to_f
        previous_cost = workflow_runs.where(ai_workflow_runs: { created_at: previous_start..start_time }).sum(:total_cost).to_f

        change = previous_cost.zero? ? nil : ((current_cost - previous_cost) / previous_cost * 100).round(2)

        {
          current_period_cost: current_cost.round(6),
          previous_period_cost: previous_cost.round(6),
          change_percentage: change,
          trend_direction: change.nil? ? "unknown" : (change.positive? ? "increasing" : "decreasing")
        }
      end

      private

      def workflows
        account.ai_workflows
      end

      def agents
        account.ai_agents
      end

      def workflow_runs
        ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: account.id })
      end

      def node_executions
        ::Ai::WorkflowNodeExecution.joins(workflow_run: :workflow).where(ai_workflows: { account_id: account.id })
      end
    end
  end
end
