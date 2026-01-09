# frozen_string_literal: true

module Monitoring
  # UnifiedService - Single consolidated monitoring service
  #
  # Replaces:
  # - AiMonitoringService
  # - AiComprehensiveMonitoringService
  # - Multiple monitoring controllers
  #
  # Provides unified monitoring for:
  # - System health and performance
  # - AI providers
  # - Agents
  # - Workflows
  # - Conversations
  # - Costs and resource utilization
  #
  # Usage:
  #   service = Monitoring::UnifiedService.new(account: account)
  #   dashboard = service.get_dashboard_metrics(time_range: 1.hour)
  #
  class UnifiedService
  include BaseAiService
  include AiMonitoringConcern

  # Component types for monitoring
  COMPONENTS = %w[system providers agents workflows conversations costs resources].freeze

  # =============================================================================
  # UNIFIED DASHBOARD
  # =============================================================================

  # Get complete monitoring dashboard
  #
  # @param time_range [ActiveSupport::Duration] Time range for metrics
  # @param components [Array<String>] Components to include
  # @return [Hash] Complete dashboard data
  def get_dashboard(time_range: 1.hour, components: COMPONENTS)
    with_monitoring("get_dashboard", { time_range: time_range }) do
      dashboard = {
        timestamp: Time.current.iso8601,
        time_range_seconds: time_range.to_i,
        overview: get_system_overview,
        health_score: calculate_health_score,
        components: {}
      }

      # Collect metrics for requested components
      components.each do |component|
        dashboard[:components][component] = collect_component_metrics(component, time_range)
      end

      dashboard
    end
  end

  # Get system overview metrics
  #
  # @return [Hash] System overview
  def get_system_overview
    {
      status: determine_health_status,
      active_workflows: count_active_workflows,
      active_agents: count_active_agents,
      total_executions_today: count_executions_today,
      total_cost_today: calculate_cost_today,
      avg_response_time: get_avg_response_time,
      success_rate: get_success_rate
    }
  end

  # Calculate overall health score (0-100)
  #
  # @return [Integer] Health score
  def calculate_health_score
    scores = []

    # Provider health (25%)
    scores << (get_provider_health_percentage * 0.25)

    # Success rate (25%)
    scores << (get_success_rate * 0.25)

    # Performance (25%)
    perf_score = calculate_performance_score
    scores << (perf_score * 0.25)

    # Resource utilization (25%)
    resource_score = calculate_resource_score
    scores << (resource_score * 0.25)

    scores.sum.round
  end

  # =============================================================================
  # COMPONENT METRICS
  # =============================================================================

  # Collect metrics for specific component
  #
  # @param component [String] Component name
  # @param time_range [ActiveSupport::Duration] Time range
  # @return [Hash] Component metrics
  def collect_component_metrics(component, time_range)
    case component
    when "system"
      get_system_metrics(time_range)
    when "providers"
      get_provider_metrics(time_range)
    when "agents"
      get_agent_metrics(time_range)
    when "workflows"
      get_workflow_metrics(time_range)
    when "conversations"
      get_conversation_metrics(time_range)
    when "costs"
      get_cost_metrics(time_range)
    when "resources"
      get_resource_metrics(time_range)
    else
      {}
    end
  end

  # =============================================================================
  # SYSTEM METRICS
  # =============================================================================

  def get_system_metrics(time_range)
    {
      health: check_system_health,
      performance: get_system_performance(time_range),
      errors: get_error_metrics(time_range),
      uptime: calculate_uptime
    }
  end

  def get_system_performance(time_range)
    {
      avg_response_time: get_avg_response_time(time_range),
      p95_response_time: get_p95_response_time(time_range),
      requests_per_second: get_requests_per_second(time_range),
      active_connections: get_active_connections
    }
  end

  # =============================================================================
  # PROVIDER METRICS
  # =============================================================================

  def get_provider_metrics(time_range)
    providers = get_account_providers

    {
      total_providers: providers.count,
      active_providers: providers.where(status: "active").count,
      providers: providers.map { |provider| provider_summary(provider, time_range) },
      aggregated: aggregate_provider_metrics(providers, time_range)
    }
  end

  def provider_summary(provider, time_range)
    {
      id: provider.id,
      name: provider.name,
      status: provider.status,
      executions: count_provider_executions(provider, time_range),
      success_rate: calculate_provider_success_rate(provider, time_range),
      avg_response_time: get_provider_avg_response_time(provider, time_range),
      total_cost: calculate_provider_cost(provider, time_range),
      circuit_breaker_status: get_circuit_breaker_status(provider)
    }
  end

  # =============================================================================
  # AGENT METRICS
  # =============================================================================

  def get_agent_metrics(time_range)
    agents = get_account_agents

    {
      total_agents: agents.count,
      active_agents: agents.where(status: "active").count,
      agents: agents.limit(10).map { |agent| agent_summary(agent, time_range) },
      aggregated: aggregate_agent_metrics(agents, time_range)
    }
  end

  def agent_summary(agent, time_range)
    {
      id: agent.id,
      name: agent.name,
      status: agent.status,
      executions: count_agent_executions(agent, time_range),
      success_rate: calculate_agent_success_rate(agent, time_range),
      avg_execution_time: get_agent_avg_execution_time(agent, time_range),
      total_cost: calculate_agent_cost(agent, time_range)
    }
  end

  # =============================================================================
  # WORKFLOW METRICS
  # =============================================================================

  def get_workflow_metrics(time_range)
    workflows = get_account_workflows

    {
      total_workflows: workflows.count,
      active_workflows: workflows.active.count,
      workflows: workflows.limit(10).map { |workflow| workflow_summary(workflow, time_range) },
      aggregated: aggregate_workflow_metrics(workflows, time_range)
    }
  end

  def workflow_summary(workflow, time_range)
    runs = workflow.runs.where("created_at >= ?", time_range.ago)

    {
      id: workflow.id,
      name: workflow.name,
      status: workflow.status,
      total_runs: runs.count,
      successful_runs: runs.where(status: "completed").count,
      failed_runs: runs.where(status: "failed").count,
      success_rate: calculate_success_rate(
        runs.where(status: "completed").count,
        runs.count
      ),
      avg_duration: runs.average(:duration_ms)&.to_f || 0,
      total_cost: runs.sum(:total_cost) || 0
    }
  end

  # =============================================================================
  # CONVERSATION METRICS
  # =============================================================================

  def get_conversation_metrics(time_range)
    conversations = get_account_conversations(time_range)

    {
      total_conversations: conversations.count,
      active_conversations: conversations.where(status: "active").count,
      avg_message_count: conversations.average("message_count")&.to_f || 0,
      total_messages: get_total_messages(time_range),
      avg_response_time: get_conversation_avg_response_time(time_range)
    }
  end

  # =============================================================================
  # COST METRICS
  # =============================================================================

  def get_cost_metrics(time_range)
    {
      total_cost: calculate_total_cost(time_range),
      cost_by_provider: calculate_cost_by_provider(time_range),
      cost_by_agent: calculate_cost_by_agent(time_range),
      cost_by_workflow: calculate_cost_by_workflow(time_range),
      cost_trend: calculate_cost_trend(time_range),
      projected_monthly_cost: project_monthly_cost(time_range)
    }
  end

  # =============================================================================
  # RESOURCE METRICS
  # =============================================================================

  def get_resource_metrics(time_range)
    {
      database: get_database_metrics,
      redis: get_redis_metrics,
      memory: get_memory_metrics,
      cpu: get_cpu_metrics
    }
  end

  # =============================================================================
  # ALERTS
  # =============================================================================

  # Get all active alerts
  #
  # @param filters [Hash] Filter criteria
  # @return [Hash] Alert data
  def get_alerts(filters = {})
    alerts = get_active_alerts(filters)

    {
      total_alerts: alerts.count,
      by_severity: group_by_severity(alerts),
      by_type: group_by_type(alerts),
      recent_alerts: alerts.first(10)
    }
  end

  # Check all metrics and trigger alerts as needed
  #
  # @return [Array<Hash>] Triggered alerts
  def check_and_trigger_alerts
    metrics = get_dashboard(time_range: 1.hour)

    check_alerts(metrics[:overview])
  end

  private

  # =============================================================================
  # QUERY HELPERS
  # =============================================================================

  def get_account_providers
    return Ai::Provider.none unless @account

    @account.ai_providers.includes(:provider_credentials)
  end

  def get_account_agents
    return Ai::Agent.none unless @account

    @account.ai_agents.includes(:provider)
  end

  def get_account_workflows
    return Ai::Workflow.none unless @account

    @account.ai_workflows.includes(:ai_workflow_runs)
  end

  def get_account_conversations(time_range)
    return Ai::Conversation.none unless @account

    @account.ai_conversations.where("created_at >= ?", time_range.ago)
  end

  # =============================================================================
  # CALCULATION HELPERS
  # =============================================================================

  def count_active_workflows
    return 0 unless @account

    @account.ai_workflows.with_active_runs.count
  end

  def count_active_agents
    return 0 unless @account

    @account.ai_agents.where(status: "active").count
  end

  def count_executions_today
    Ai::WorkflowRun.where(account: @account)
                 .where("created_at >= ?", Time.current.beginning_of_day)
                 .count
  end

  def calculate_cost_today
    Ai::WorkflowRun.where(account: @account)
                 .where("created_at >= ?", Time.current.beginning_of_day)
                 .sum(:total_cost) || 0.0
  end

  def get_avg_response_time(time_range = 1.hour)
    metrics = get_metrics("response_time", start_time: time_range.ago)
    aggregate_metrics(metrics)[:avg]
  end

  def get_p95_response_time(time_range = 1.hour)
    metrics = get_metrics("response_time", start_time: time_range.ago)
    aggregate_metrics(metrics)[:p95]
  end

  def get_success_rate(time_range = 1.hour)
    runs = Ai::WorkflowRun.where(account: @account)
                       .where("created_at >= ?", time_range.ago)

    calculate_success_rate(
      runs.where(status: "completed").count,
      runs.count
    )
  end

  def get_provider_health_percentage
    providers = get_account_providers.where(status: "active")
    return 100 if providers.empty?

    healthy_count = providers.count { |p| provider_is_healthy?(p) }
    (healthy_count.to_f / providers.count * 100).round
  end

  def provider_is_healthy?(provider)
    # Check recent execution success rate
    recent_executions = Ai::AgentExecution.where(provider: provider)
                                       .where("created_at >= ?", 5.minutes.ago)

    return true if recent_executions.empty?

    success_rate = calculate_success_rate(
      recent_executions.where(status: "completed").count,
      recent_executions.count
    )

    success_rate >= 95.0
  end

  def calculate_performance_score
    avg_time = get_avg_response_time
    return 100 if avg_time.zero?

    # Score based on response time (lower is better)
    # 0-1000ms = 100, 1000-5000ms = 75, 5000+ = 50
    if avg_time < 1000
      100
    elsif avg_time < 5000
      75
    else
      50
    end
  end

  def calculate_resource_score
    # Simple resource health check
    db_health = check_database_health
    redis_health = check_redis_health

    scores = []
    scores << (db_health[:status] == "healthy" ? 100 : 0)
    scores << (redis_health[:status] == "healthy" ? 100 : 0)

    scores.sum / scores.count
  end

  def group_by_severity(alerts)
    alerts.group_by { |a| a[:severity] }
          .transform_values(&:count)
  end

  def group_by_type(alerts)
    alerts.group_by { |a| a[:alert_type] }
          .transform_values(&:count)
  end

  # Stub methods for metrics that need implementation
  def count_provider_executions(provider, time_range)
    Ai::AgentExecution.where(provider: provider)
                   .where("created_at >= ?", time_range.ago)
                   .count
  end

  def calculate_provider_success_rate(provider, time_range)
    executions = Ai::AgentExecution.where(provider: provider)
                                .where("created_at >= ?", time_range.ago)

    calculate_success_rate(
      executions.where(status: "completed").count,
      executions.count
    )
  end

  def get_provider_avg_response_time(provider, time_range)
    Ai::AgentExecution.where(provider: provider)
                   .where("created_at >= ?", time_range.ago)
                   .average(:duration_ms)&.to_f || 0
  end

  def calculate_provider_cost(provider, time_range)
    Ai::AgentExecution.where(provider: provider)
                   .where("created_at >= ?", time_range.ago)
                   .sum(:cost_usd) || 0.0
  end

  def get_circuit_breaker_status(provider)
    breaker = CircuitBreaker.find_by(
      service: "ai_provider_#{provider.id}",
      circuit_type: "provider"
    )

    return "closed" unless breaker

    {
      state: breaker.state,
      failure_count: breaker.failure_count,
      last_failure_at: breaker.last_failure_at&.iso8601,
      next_retry_at: breaker.state == "open" ? (breaker.last_failure_at + breaker.reset_timeout_seconds.seconds)&.iso8601 : nil
    }
  end

  def count_agent_executions(agent, time_range)
    agent.executions.where("created_at >= ?", time_range.ago).count
  end

  def calculate_agent_success_rate(agent, time_range)
    executions = agent.executions.where("created_at >= ?", time_range.ago)

    calculate_success_rate(
      executions.where(status: "completed").count,
      executions.count
    )
  end

  def get_agent_avg_execution_time(agent, time_range)
    agent.executions
         .where("created_at >= ?", time_range.ago)
         .average(:duration_ms)&.to_f || 0
  end

  def calculate_agent_cost(agent, time_range)
    agent.executions
         .where("created_at >= ?", time_range.ago)
         .sum(:cost_usd) || 0.0
  end

  def aggregate_provider_metrics(providers, time_range)
    {
      total_executions: providers.sum { |p| count_provider_executions(p, time_range) },
      avg_success_rate: providers.map { |p| calculate_provider_success_rate(p, time_range) }.sum / [ providers.count, 1 ].max,
      total_cost: providers.sum { |p| calculate_provider_cost(p, time_range) }
    }
  end

  def aggregate_agent_metrics(agents, time_range)
    {
      total_executions: agents.sum { |a| count_agent_executions(a, time_range) },
      avg_success_rate: agents.map { |a| calculate_agent_success_rate(a, time_range) }.sum / [ agents.count, 1 ].max,
      total_cost: agents.sum { |a| calculate_agent_cost(a, time_range) }
    }
  end

  def aggregate_workflow_metrics(workflows, time_range)
    all_runs = Ai::WorkflowRun.where(workflow: workflows)
                           .where("created_at >= ?", time_range.ago)

    {
      total_runs: all_runs.count,
      successful_runs: all_runs.where(status: "completed").count,
      failed_runs: all_runs.where(status: "failed").count,
      success_rate: calculate_success_rate(
        all_runs.where(status: "completed").count,
        all_runs.count
      ),
      total_cost: all_runs.sum(:total_cost) || 0
    }
  end

  def get_total_messages(time_range)
    Ai::Message.joins(:ai_conversation)
            .where(ai_conversations: { account: @account })
            .where("ai_messages.created_at >= ?", time_range.ago)
            .count
  end

  def get_conversation_avg_response_time(time_range)
    # Calculate average time between user message and AI response
    messages = Ai::Message.joins(:ai_conversation)
                       .where(ai_conversations: { account: @account })
                       .where("ai_messages.created_at >= ?", time_range.ago)
                       .order(:created_at)

    return 0 if messages.count < 2

    response_times = []
    user_message_time = nil

    messages.each do |message|
      if message.role == "user"
        user_message_time = message.created_at
      elsif message.role == "assistant" && user_message_time
        response_times << (message.created_at - user_message_time) * 1000 # Convert to ms
        user_message_time = nil
      end
    end

    return 0 if response_times.empty?

    (response_times.sum / response_times.count).round(2)
  end

  def calculate_total_cost(time_range)
    workflow_cost = Ai::WorkflowRun.where(account: @account)
                                .where("created_at >= ?", time_range.ago)
                                .sum(:total_cost) || 0.0

    agent_cost = Ai::AgentExecution.joins(:agent)
                                .where(ai_agents: { account: @account })
                                .where("ai_agent_executions.created_at >= ?", time_range.ago)
                                .sum(:cost_usd) || 0.0

    workflow_cost + agent_cost
  end

  def calculate_cost_by_provider(time_range)
    Ai::AgentExecution.joins(agent: :provider)
                   .where(ai_agents: { account: @account })
                   .where("ai_agent_executions.created_at >= ?", time_range.ago)
                   .group("ai_providers.id", "ai_providers.name")
                   .select("ai_providers.id as provider_id",
                          "ai_providers.name as provider_name",
                          "SUM(ai_agent_executions.cost_usd) as total_cost",
                          "COUNT(ai_agent_executions.id) as execution_count")
                   .map do |result|
      {
        provider_id: result.provider_id,
        provider_name: result.provider_name,
        total_cost: result.total_cost&.to_f || 0.0,
        execution_count: result.execution_count
      }
    end
  end

  def calculate_cost_by_agent(time_range)
    Ai::AgentExecution.joins(:agent)
                   .where(ai_agents: { account: @account })
                   .where("ai_agent_executions.created_at >= ?", time_range.ago)
                   .group("ai_agents.id", "ai_agents.name")
                   .select("ai_agents.id as agent_id",
                          "ai_agents.name as agent_name",
                          "SUM(ai_agent_executions.cost_usd) as total_cost",
                          "COUNT(ai_agent_executions.id) as execution_count")
                   .map do |result|
      {
        agent_id: result.agent_id,
        agent_name: result.agent_name,
        total_cost: result.total_cost&.to_f || 0.0,
        execution_count: result.execution_count
      }
    end
  end

  def calculate_cost_by_workflow(time_range)
    Ai::WorkflowRun.joins(:ai_workflow)
                .where(ai_workflows: { account: @account })
                .where("ai_workflow_runs.created_at >= ?", time_range.ago)
                .group("ai_workflows.id", "ai_workflows.name")
                .select("ai_workflows.id as workflow_id",
                       "ai_workflows.name as workflow_name",
                       "SUM(ai_workflow_runs.total_cost) as total_cost",
                       "COUNT(ai_workflow_runs.id) as run_count")
                .map do |result|
      {
        workflow_id: result.workflow_id,
        workflow_name: result.workflow_name,
        total_cost: result.total_cost&.to_f || 0.0,
        run_count: result.run_count
      }
    end
  end

  def calculate_cost_trend(time_range)
    # Calculate daily cost trend for the time range
    workflow_costs = Ai::WorkflowRun.where(account: @account)
                                  .where("created_at >= ?", time_range.ago)
                                  .group("DATE(created_at)")
                                  .select("DATE(created_at) as date",
                                         "SUM(total_cost) as daily_cost")

    agent_costs = Ai::AgentExecution.joins(:agent)
                                 .where(ai_agents: { account: @account })
                                 .where("ai_agent_executions.created_at >= ?", time_range.ago)
                                 .group("DATE(ai_agent_executions.created_at)")
                                 .select("DATE(ai_agent_executions.created_at) as date",
                                        "SUM(cost_usd) as daily_cost")

    # Merge workflow and agent costs by date
    all_costs = {}
    workflow_costs.each { |c| all_costs[c.date.to_s] = (all_costs[c.date.to_s] || 0) + (c.daily_cost&.to_f || 0) }
    agent_costs.each { |c| all_costs[c.date.to_s] = (all_costs[c.date.to_s] || 0) + (c.daily_cost&.to_f || 0) }

    all_costs.map do |date, cost|
      {
        date: date,
        total_cost: cost.round(2)
      }
    end.sort_by { |d| d[:date] }
  end

  def project_monthly_cost(time_range)
    daily_average = calculate_total_cost(time_range) / (time_range.to_f / 1.day)
    (daily_average * 30).round(2)
  end

  def get_database_metrics
    {
      status: check_database_health[:status],
      connection_count: ActiveRecord::Base.connection_pool.stat[:size]
    }
  end

  def get_redis_metrics
    info = redis.info
    {
      status: check_redis_health[:status],
      used_memory: info["used_memory_human"],
      connected_clients: info["connected_clients"]&.to_i || 0
    }
  end

  def get_memory_metrics
    # Get memory usage from system
    if `which free`.present?
      # Linux/Unix systems
      free_output = `free -m`
      lines = free_output.split("\n")
      mem_line = lines[1]
      parts = mem_line.split

      {
        total_mb: parts[1].to_i,
        used_mb: parts[2].to_i,
        free_mb: parts[3].to_i,
        usage_percent: ((parts[2].to_f / parts[1].to_f) * 100).round(2)
      }
    else
      # Fallback - use Ruby process memory
      rss = `ps -o rss= -p #{Process.pid}`.to_i / 1024
      {
        process_memory_mb: rss,
        usage_percent: 0
      }
    end
  rescue => e
    Rails.logger.warn "Failed to collect memory metrics: #{e.message}"
    {}
  end

  def get_cpu_metrics
    # Get CPU usage from system
    if `which top`.present?
      # Get CPU usage from top command (works on most Unix systems)
      cpu_output = `top -bn1 | grep "Cpu(s)"`.strip

      if cpu_output.present?
        # Parse output like: "Cpu(s): 12.5%us,  2.3%sy,  0.0%ni, 84.1%id,  0.0%wa"
        idle = cpu_output.match(/(\d+\.?\d*)%?\s*id/)[1].to_f rescue 0
        used_percent = (100 - idle).round(2)
        load_avg = (`uptime`.match(/load average: ([\d., ]+)/)&.[](1) || "N/A")

        {
          usage_percent: used_percent,
          idle_percent: idle.round(2),
          load_average: load_avg
        }
      else
        fallback_cpu_metrics
      end
    else
      fallback_cpu_metrics
    end
  rescue => e
    Rails.logger.warn "Failed to collect CPU metrics: #{e.message}"
    fallback_cpu_metrics
  end

  def fallback_cpu_metrics
    load_avg = `cat /proc/loadavg 2>/dev/null`.split[0..2].join(", ") rescue "N/A"
    {
      load_average: load_avg,
      usage_percent: 0
    }
  end

  def get_requests_per_second(time_range)
    # Calculate requests per second from workflow runs and agent executions
    workflow_requests = Ai::WorkflowRun.where(account: @account)
                                    .where("created_at >= ?", time_range.ago)
                                    .count

    agent_requests = Ai::AgentExecution.joins(:agent)
                                    .where(ai_agents: { account: @account })
                                    .where("ai_agent_executions.created_at >= ?", time_range.ago)
                                    .count

    total_requests = workflow_requests + agent_requests
    time_window_seconds = time_range.to_f

    return 0 if time_window_seconds.zero?

    (total_requests.to_f / time_window_seconds).round(3)
  end

  def get_active_connections
    # Get active connections from database and Redis
    db_connections = ActiveRecord::Base.connection_pool.stat[:busy] || 0

    redis_connections = begin
      redis.info["connected_clients"]&.to_i || 0
    rescue => e
      Rails.logger.warn "Failed to get Redis connections: #{e.message}"
      0
    end

    {
      database: db_connections,
      redis: redis_connections,
      total: db_connections + redis_connections
    }
  end

  def get_error_metrics(time_range)
    # Count failed workflow runs and agent executions
    failed_workflows = Ai::WorkflowRun.where(account: @account)
                                   .where("created_at >= ?", time_range.ago)
                                   .where(status: "failed")
                                   .count

    failed_agents = Ai::AgentExecution.joins(:agent)
                                   .where(ai_agents: { account: @account })
                                   .where("ai_agent_executions.created_at >= ?", time_range.ago)
                                   .where(status: "failed")
                                   .count

    total_workflows = Ai::WorkflowRun.where(account: @account)
                                  .where("created_at >= ?", time_range.ago)
                                  .count

    total_agents = Ai::AgentExecution.joins(:agent)
                                  .where(ai_agents: { account: @account })
                                  .where("ai_agent_executions.created_at >= ?", time_range.ago)
                                  .count

    total_errors = failed_workflows + failed_agents
    total_requests = total_workflows + total_agents

    error_rate = total_requests > 0 ? ((total_errors.to_f / total_requests) * 100).round(2) : 0.0

    {
      total_errors: total_errors,
      failed_workflows: failed_workflows,
      failed_agents: failed_agents,
      error_rate: error_rate
    }
  end
  end
end

