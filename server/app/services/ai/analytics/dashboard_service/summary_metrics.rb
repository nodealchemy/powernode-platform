# frozen_string_literal: true

module Ai
  module Analytics
    class DashboardService
      module SummaryMetrics
        extend ActiveSupport::Concern

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
          agent_cost = agent_executions.where("ai_agent_executions.created_at >= ?", since).sum(:cost_usd).to_f
          (workflow_cost + agent_cost).round(6)
        end

        def calculate_period_cost(start_time, end_time)
          workflow_cost = workflow_runs.where(ai_workflow_runs: { created_at: start_time..end_time }).sum(:total_cost).to_f
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

        def provider_usage
          {}
        end

        def model_usage
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
          0
        end
      end
    end
  end
end
