# frozen_string_literal: true

module Orchestration
  module Monitoring
    def monitor_executions
      active_executions = @account.ai_agent_executions.where(status: ["pending", "running"])

      monitoring_results = {
        total_active: active_executions.count,
        by_status: active_executions.group(:status).count,
        by_provider: active_executions.joins(:ai_provider).group("ai_providers.name").count,
        resource_usage: calculate_resource_usage(active_executions),
        performance_metrics: calculate_performance_metrics(active_executions)
      }

      check_for_stuck_executions(active_executions)
      check_resource_constraints(active_executions)

      monitoring_results
    end

    def get_system_status
      return {} unless @account&.id

      active_executions = @account.ai_agent_executions.where(status: ["queued", "processing"])
      recent_executions = @account.ai_agent_executions.where(created_at: 1.hour.ago..Time.current)

      providers = @account.ai_providers.active
      provider_status = providers.map do |provider|
        current_load = calculate_provider_current_load(provider)
        max_load = provider.metadata&.dig("max_concurrent") || 10

        {
          id: provider.id,
          name: provider.name,
          status: current_load < max_load ? "available" : "at_capacity",
          current_load: current_load,
          max_capacity: max_load,
          success_rate: calculate_provider_success_rate(provider)
        }
      end

      active_workflows = @account.ai_workflow_executions.where(status: ["pending", "running"])

      {
        account_id: @account.id,
        active_executions: active_executions.count,
        recent_executions: recent_executions.count,
        active_workflows: active_workflows.count,
        providers: provider_status,
        system_load: calculate_system_load_percentage(active_executions, @account),
        last_activity: recent_executions.maximum(:created_at) || 1.day.ago,
        overall_health: determine_system_health(recent_executions, active_executions)
      }
    end

    private

    def calculate_resource_usage(executions)
      {}
    end

    def calculate_performance_metrics(executions)
      {}
    end

    def check_for_stuck_executions(executions)
    end

    def check_resource_constraints(executions)
    end

    def calculate_provider_current_load(provider)
      provider.ai_agent_executions.where(status: ["pending", "running"]).count
    end

    def calculate_provider_avg_response_time(provider)
      provider.ai_agent_executions.where(created_at: 24.hours.ago..Time.current).average(:duration_ms) || 1000
    end

    def calculate_provider_success_rate(provider)
      executions = provider.ai_agent_executions.where(created_at: 24.hours.ago..Time.current)
      return 95 if executions.empty?
      successful = executions.where(status: "completed").count
      (successful.to_f / executions.count * 100).round(2)
    end

    def calculate_system_load_percentage(active_executions, account)
      max_concurrent = account.subscription&.ai_execution_limit || 10
      current_load = active_executions.count

      return 0 if max_concurrent == 0
      [(current_load.to_f / max_concurrent * 100).round(1), 100.0].min
    end

    def determine_system_health(recent_executions, active_executions)
      return "idle" if recent_executions.empty? && active_executions.empty?

      if recent_executions.any?
        success_rate = calculate_recent_success_rate(recent_executions)

        case success_rate
        when 90..100
          "excellent"
        when 75..89
          "good"
        when 50..74
          "degraded"
        else
          "poor"
        end
      else
        active_executions.any? ? "active" : "idle"
      end
    end

    def calculate_recent_success_rate(executions)
      return 100.0 if executions.empty?

      successful = executions.where(status: "completed").count
      (successful.to_f / executions.count * 100).round(1)
    end

    def calculate_workflow_progress(workflow_execution)
      case workflow_execution.status
      when "completed"
        100
      when "failed", "cancelled"
        workflow_execution.metadata.dig("progress_percentage") || 0
      when "running"
        workflow_execution.metadata.dig("progress_percentage") || 25
      when "pending", "initializing"
        0
      else
        0
      end
    end
  end
end
