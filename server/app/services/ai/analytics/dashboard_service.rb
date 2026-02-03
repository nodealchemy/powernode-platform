# frozen_string_literal: true

module Ai
  module Analytics
    # Service for generating AI analytics dashboard data
    #
    # Consolidates dashboard generation logic from AnalyticsController including:
    # - Summary metrics and KPIs
    # - Trend analysis
    # - Quick stats and highlights
    # - Real-time metrics
    #
    # Usage:
    #   service = Ai::Analytics::DashboardService.new(account: current_account, time_range: 30.days)
    #   dashboard = service.generate
    #
    class DashboardService
      attr_reader :account, :time_range

      # Cache TTLs
      DASHBOARD_CACHE_TTL = 15.minutes
      REAL_TIME_CACHE_TTL = 1.minute

      # Initialize the service
      # @param account [Account] Account to analyze
      # @param time_range [ActiveSupport::Duration] Time range for analysis
      def initialize(account:, time_range: 30.days)
        @account = account
        @time_range = time_range
      end

      # Generate complete dashboard data (cached for 15 minutes)
      # @param force_refresh [Boolean] Skip cache and regenerate
      # @return [Hash] Dashboard data
      def generate(force_refresh: false)
        cache_key = "ai:dashboard:#{account.id}:#{time_range.to_i}"

        return Rails.cache.fetch(cache_key, expires_in: DASHBOARD_CACHE_TTL, force: force_refresh) do
          {
            summary: generate_summary_metrics,
            trends: generate_trend_data,
            highlights: generate_highlights,
            quick_stats: generate_quick_stats,
            resource_usage: generate_resource_usage,
            recent_activity: generate_recent_activity
          }
        end
      end

      # Invalidate dashboard cache for an account
      def self.invalidate_cache(account_id)
        Rails.cache.delete_matched("ai:dashboard:#{account_id}:*")
      end

      # Generate summary metrics
      # @return [Hash] Summary metrics
      def generate_summary_metrics
        start_time = time_range.ago

        {
          workflows: {
            total: workflows.count,
            active: workflows.where(status: "active").count,
            executions: workflow_runs.where("ai_workflow_runs.created_at >= ?", start_time).count,
            success_rate: calculate_workflow_success_rate(start_time)
          },
          agents: {
            total: agents.count,
            active: agents.active.count,
            executions: agent_executions.where("ai_agent_executions.created_at >= ?", start_time).count,
            success_rate: calculate_agent_success_rate(start_time)
          },
          conversations: {
            total: conversations.count,
            active: conversations.where(status: %w[active in_progress]).count,
            messages: messages.where("ai_messages.created_at >= ?", start_time).count
          },
          cost: {
            total: calculate_total_cost(start_time),
            trend: calculate_cost_trend(start_time),
            budget_utilization: calculate_budget_utilization
          }
        }
      end

      # Generate trend data for charts
      # @return [Hash] Trend data
      def generate_trend_data
        start_time = time_range.ago

        {
          executions_by_day: executions_by_day(start_time),
          cost_by_day: cost_by_day(start_time),
          success_rate_by_day: success_rate_by_day(start_time),
          messages_by_day: messages_by_day(start_time)
        }
      end

      # Generate dashboard highlights
      # @return [Hash] Highlights
      def generate_highlights
        start_time = time_range.ago

        {
          top_workflows: top_workflows(start_time, limit: 5),
          top_agents: top_agents(start_time, limit: 5),
          recent_failures: recent_failures(start_time, limit: 5),
          cost_leaders: cost_leaders(start_time, limit: 5)
        }
      end

      # Generate quick stats
      # @return [Hash] Quick stats
      def generate_quick_stats
        today = Date.current.beginning_of_day
        yesterday = 1.day.ago.beginning_of_day

        {
          today: {
            executions: workflow_runs.where("ai_workflow_runs.created_at >= ?", today).count,
            cost: calculate_period_cost(today, Time.current),
            messages: messages.where("ai_messages.created_at >= ?", today).count
          },
          yesterday: {
            executions: workflow_runs.where("ai_workflow_runs.created_at >= ? AND ai_workflow_runs.created_at < ?", yesterday, today).count,
            cost: calculate_period_cost(yesterday, today),
            messages: messages.where("ai_messages.created_at >= ? AND ai_messages.created_at < ?", yesterday, today).count
          },
          this_week: {
            executions: workflow_runs.where("ai_workflow_runs.created_at >= ?", 1.week.ago).count,
            cost: calculate_period_cost(1.week.ago, Time.current),
            messages: messages.where("ai_messages.created_at >= ?", 1.week.ago).count
          }
        }
      end

      # Generate resource usage data
      # @return [Hash] Resource usage
      def generate_resource_usage
        {
          providers: provider_usage,
          models: model_usage,
          tokens: token_usage
        }
      end

      # Generate recent activity feed
      # @param limit [Integer] Number of activities to return
      # @return [Array<Hash>] Recent activities
      def generate_recent_activity(limit: 20)
        activities = []

        # Recent workflow runs
        workflow_runs.includes(:workflow, :triggered_by_user)
                     .order(created_at: :desc)
                     .limit(limit / 2)
                     .each do |run|
          activities << {
            type: "workflow_run",
            status: run.status,
            resource_name: run.workflow.name,
            user: run.triggered_by_user&.email,
            created_at: run.created_at.iso8601
          }
        end

        # Recent conversations
        conversations.includes(:user)
                     .order(created_at: :desc)
                     .limit(limit / 2)
                     .each do |conv|
          activities << {
            type: "conversation",
            status: conv.status,
            resource_name: conv.title || "Conversation",
            user: conv.user&.email,
            created_at: conv.created_at.iso8601
          }
        end

        activities.sort_by { |a| a[:created_at] }.reverse.first(limit)
      end

      # Generate real-time metrics (for live dashboards, cached for 1 minute)
      # @param force_refresh [Boolean] Skip cache
      # @return [Hash] Real-time metrics
      def real_time_metrics(force_refresh: false)
        cache_key = "ai:dashboard:realtime:#{account.id}"

        Rails.cache.fetch(cache_key, expires_in: REAL_TIME_CACHE_TTL, force: force_refresh) do
          {
            active_executions: workflow_runs.where(status: %w[running initializing]).count,
            active_conversations: conversations.where(status: %w[active in_progress]).count,
            queue_depth: pending_jobs_count,
            error_rate_last_hour: calculate_error_rate(1.hour.ago),
            avg_response_time_last_hour: calculate_avg_response_time(1.hour.ago),
            timestamp: Time.current.iso8601
          }
        end
      end

      private

      # =============================================================================
      # QUERY HELPERS
      # =============================================================================

      def workflows
        account.ai_workflows
      end

      def agents
        account.ai_agents
      end

      def workflow_runs
        ::Ai::WorkflowRun.joins(:workflow).where(ai_workflows: { account_id: account.id })
      end

      def agent_executions
        ::Ai::AgentExecution.joins(:agent).where(ai_agents: { account_id: account.id })
      end

      def conversations
        account.ai_conversations
      end

      def messages
        ::Ai::Message.joins(:conversation).where(ai_conversations: { account_id: account.id })
      end

      # =============================================================================
      # CALCULATION HELPERS
      # =============================================================================

      def calculate_workflow_success_rate(since)
        total = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).where.not(status: %w[running initializing pending]).count
        return nil if total.zero?

        completed = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).where(status: "completed").count
        (completed.to_f / total).round(4)
      end

      def calculate_agent_success_rate(since)
        total = agent_executions.where("ai_agent_executions.created_at >= ?", since).where.not(status: %w[running pending]).count
        return nil if total.zero?

        completed = agent_executions.where("ai_agent_executions.created_at >= ?", since).where(status: "completed").count
        (completed.to_f / total).round(4)
      end

      def calculate_total_cost(since)
        workflow_cost = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).sum(:total_cost).to_f
        # ai_agent_executions uses cost_usd column, not total_cost
        agent_cost = agent_executions.where("ai_agent_executions.created_at >= ?", since).sum(:cost_usd).to_f
        (workflow_cost + agent_cost).round(6)
      end

      def calculate_period_cost(start_time, end_time)
        workflow_cost = workflow_runs.where(ai_workflow_runs: { created_at: start_time..end_time }).sum(:total_cost).to_f
        # ai_agent_executions uses cost_usd column, not total_cost
        agent_cost = agent_executions.where(ai_agent_executions: { created_at: start_time..end_time }).sum(:cost_usd).to_f
        (workflow_cost + agent_cost).round(6)
      end

      def calculate_cost_trend(since)
        previous_period_start = since - time_range
        current_cost = calculate_total_cost(since)
        previous_cost = calculate_period_cost(previous_period_start, since)

        return nil if previous_cost.zero?

        ((current_cost - previous_cost) / previous_cost * 100).round(2)
      end

      def calculate_budget_utilization
        budget = account.settings&.dig("ai_budget_limit") || Float::INFINITY
        return nil if budget.infinite?

        current_cost = calculate_total_cost(time_range.ago)
        ((current_cost / budget) * 100).round(2)
      end

      def calculate_error_rate(since)
        total = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).count
        return 0.0 if total.zero?

        failed = workflow_runs.where("ai_workflow_runs.created_at >= ?", since).where(status: "failed").count
        (failed.to_f / total * 100).round(2)
      end

      def calculate_avg_response_time(since)
        avg = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                          .where(status: "completed")
                          .where.not(duration_ms: nil)
                          .average(:duration_ms)
        avg&.to_f&.round(2)
      end

      # =============================================================================
      # TREND DATA HELPERS
      # =============================================================================

      def executions_by_day(since)
        workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                     .group("DATE(ai_workflow_runs.created_at)")
                     .count
                     .transform_keys(&:to_s)
      end

      def cost_by_day(since)
        workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                     .group("DATE(ai_workflow_runs.created_at)")
                     .sum(:total_cost)
                     .transform_keys(&:to_s)
                     .transform_values { |v| v.to_f.round(6) }
      end

      def success_rate_by_day(since)
        completed = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                                .where(status: "completed")
                                .group("DATE(ai_workflow_runs.created_at)")
                                .count

        total = workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                            .where.not(status: %w[running initializing pending])
                            .group("DATE(ai_workflow_runs.created_at)")
                            .count

        total.transform_keys(&:to_s).transform_values do |count|
          date = total.key(count)
          next 0.0 if count.zero?

          ((completed[date] || 0).to_f / count * 100).round(2)
        end
      end

      def messages_by_day(since)
        messages.where("ai_messages.created_at >= ?", since)
               .group("DATE(ai_messages.created_at)")
               .count
               .transform_keys(&:to_s)
      end

      # =============================================================================
      # HIGHLIGHTS HELPERS
      # =============================================================================

      def top_workflows(since, limit:)
        workflows.joins(:runs)
                 .where("ai_workflow_runs.created_at >= ?", since)
                 .group("ai_workflows.id", "ai_workflows.name")
                 .order("COUNT(ai_workflow_runs.id) DESC")
                 .limit(limit)
                 .pluck("ai_workflows.id", "ai_workflows.name", Arel.sql("COUNT(ai_workflow_runs.id)"))
                 .map { |id, name, count| { id: id, name: name, execution_count: count } }
      end

      def top_agents(since, limit:)
        agents.joins(:executions)
              .where("ai_agent_executions.created_at >= ?", since)
              .group("ai_agents.id", "ai_agents.name")
              .order("COUNT(ai_agent_executions.id) DESC")
              .limit(limit)
              .pluck("ai_agents.id", "ai_agents.name", Arel.sql("COUNT(ai_agent_executions.id)"))
              .map { |id, name, count| { id: id, name: name, execution_count: count } }
      rescue StandardError
        []
      end

      def recent_failures(since, limit:)
        workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                     .where(status: "failed")
                     .includes(:workflow)
                     .order("ai_workflow_runs.created_at DESC")
                     .limit(limit)
                     .map do |run|
          {
            run_id: run.run_id,
            workflow_name: run.workflow.name,
            error: run.error_details&.dig("error_message") || "Unknown error",
            failed_at: run.completed_at&.iso8601
          }
        end
      end

      def cost_leaders(since, limit:)
        workflow_runs.where("ai_workflow_runs.created_at >= ?", since)
                     .joins(:workflow)
                     .group("ai_workflows.id", "ai_workflows.name")
                     .order(Arel.sql("SUM(ai_workflow_runs.total_cost) DESC"))
                     .limit(limit)
                     .pluck("ai_workflows.id", "ai_workflows.name", Arel.sql("SUM(ai_workflow_runs.total_cost)"))
                     .map { |id, name, cost| { id: id, name: name, total_cost: cost.to_f.round(6) } }
      end

      # =============================================================================
      # RESOURCE USAGE HELPERS
      # =============================================================================

      def provider_usage
        # Aggregate usage by provider
        {}
      end

      def model_usage
        # Aggregate usage by model
        {}
      end

      def token_usage
        total_input = 0
        total_output = 0

        workflow_runs.where("ai_workflow_runs.created_at >= ?", time_range.ago).each do |run|
          run.node_executions.each do |exec|
            usage = exec.metadata&.dig("token_usage") || {}
            total_input += usage["input_tokens"] || 0
            total_output += usage["output_tokens"] || 0
          end
        end

        {
          total_input_tokens: total_input,
          total_output_tokens: total_output,
          total_tokens: total_input + total_output
        }
      end

      def pending_jobs_count
        # Count pending Sidekiq jobs (if available)
        0
      end
    end
  end
end
