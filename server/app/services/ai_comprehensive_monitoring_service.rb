# frozen_string_literal: true

# @deprecated Use UnifiedMonitoringService instead
#   This service will be removed in v2.0
#   UnifiedMonitoringService consolidates all monitoring functionality with:
#   - Better performance (no dependency on AiMonitoringService)
#   - Unified API
#   - Comprehensive component metrics
#
#   Migration guide: docs/migration/MONITORING_SERVICE_MIGRATION.md
#
class AiComprehensiveMonitoringService
  include ActiveModel::Model
  include ActiveModel::Attributes

  COMPONENT_TYPES = %w[system providers agents workflows conversations costs alerts resources].freeze
  ALERT_SEVERITIES = %w[low medium high critical].freeze
  ALERT_TYPES = %w[
    provider_failure high_cost execution_timeout circuit_breaker_open
    low_success_rate high_latency resource_exhaustion quota_exceeded
    agent_failure workflow_failure conversation_timeout system_overload
  ].freeze

  def initialize(account: nil)
    @account = account
    @logger = Rails.logger
    @redis = Redis.new(url: Rails.application.credentials.redis_url || 'redis://localhost:6379')
    @base_monitoring_service = AiMonitoringService.new(account: account)
  end

  # Unified Dashboard Data
  def get_unified_dashboard(time_range: 1.hour, components: COMPONENT_TYPES)
    dashboard_data = {
      timestamp: Time.current.iso8601,
      overview: get_system_overview,
      health_score: calculate_system_health_score,
      components: {}
    }

    components.each do |component|
      case component
      when 'system'
        dashboard_data[:components][:system] = get_system_metrics(time_range)
      when 'providers'
        dashboard_data[:components][:providers] = get_providers_dashboard_summary(time_range)
      when 'agents'
        dashboard_data[:components][:agents] = get_agents_dashboard_summary(time_range)
      when 'workflows'
        dashboard_data[:components][:workflows] = get_workflows_dashboard_summary(time_range)
      when 'conversations'
        dashboard_data[:components][:conversations] = get_conversations_dashboard_summary(time_range)
      when 'costs'
        dashboard_data[:components][:costs] = get_costs_dashboard_summary(time_range)
      when 'alerts'
        dashboard_data[:components][:alerts] = get_alerts_dashboard_summary
      when 'resources'
        dashboard_data[:components][:resources] = get_resources_dashboard_summary
      end
    end

    dashboard_data
  end

  # System Health Comprehensive
  def get_system_health_comprehensive
    {
      overall_health: calculate_system_health_score,
      status: determine_system_status,
      components: {
        providers: get_providers_health_status,
        agents: get_agents_health_status,
        workflows: get_workflows_health_status,
        conversations: get_conversations_health_status,
        infrastructure: get_infrastructure_health_status
      },
      alerts: get_active_alerts_summary,
      recommendations: generate_health_recommendations,
      last_updated: Time.current.iso8601
    }
  end

  # Provider Monitoring
  def get_all_providers_metrics(time_range: 1.hour)
    providers = get_monitored_providers

    providers.map do |provider|
      get_provider_detailed_metrics(provider, time_range: time_range)
    end
  end

  def get_provider_detailed_metrics(provider, time_range: 1.hour)
    circuit_breaker = AiProviderCircuitBreakerService.new(provider)
    load_balancer = AiProviderLoadBalancerService.new(@account)

    {
      id: provider.id,
      name: provider.name,
      slug: provider.slug,
      status: get_provider_status(provider),
      health_score: calculate_provider_health_score(provider, time_range),
      circuit_breaker: {
        state: circuit_breaker.circuit_state,
        failure_count: circuit_breaker.failure_count,
        success_threshold: circuit_breaker.success_threshold,
        timeout: circuit_breaker.timeout,
        last_failure: circuit_breaker.last_failure_time&.iso8601,
        stats: circuit_breaker.circuit_stats
      },
      load_balancing: {
        current_load: get_provider_current_load(provider),
        weight: get_provider_weight(provider),
        utilization: get_provider_utilization(provider, time_range)
      },
      performance: {
        success_rate: get_provider_success_rate(provider, time_range),
        avg_response_time: get_provider_avg_response_time(provider, time_range),
        throughput: get_provider_throughput(provider, time_range),
        error_rate: get_provider_error_rate(provider, time_range)
      },
      usage: {
        executions_count: get_provider_executions_count(provider, time_range),
        tokens_consumed: get_provider_tokens_consumed(provider, time_range),
        cost: get_provider_cost(provider, time_range)
      },
      alerts: get_provider_alerts(provider),
      credentials: get_provider_credentials_status(provider),
      last_execution: get_provider_last_execution(provider)
    }
  end

  def get_providers_summary
    providers = get_monitored_providers
    total_providers = providers.count

    {
      total_count: total_providers,
      healthy: providers.count { |p| get_provider_status(p) == 'healthy' },
      degraded: providers.count { |p| get_provider_status(p) == 'degraded' },
      unhealthy: providers.count { |p| get_provider_status(p) == 'unhealthy' },
      circuit_breakers: {
        closed: providers.count { |p| AiProviderCircuitBreakerService.new(p).circuit_state == :closed },
        open: providers.count { |p| AiProviderCircuitBreakerService.new(p).circuit_state == :open },
        half_open: providers.count { |p| AiProviderCircuitBreakerService.new(p).circuit_state == :half_open }
      },
      active_alerts: get_providers_active_alerts_count
    }
  end

  # Agent Monitoring
  def get_all_agents_metrics(time_range: 1.hour)
    agents = get_monitored_agents

    agents.map do |agent|
      get_agent_detailed_metrics(agent, time_range: time_range)
    end
  end

  def get_agent_detailed_metrics(agent, time_range: 1.hour)
    recent_executions = agent.ai_agent_executions
                            .where('created_at > ?', Time.current - time_range)

    {
      id: agent.id,
      name: agent.name,
      status: agent.status,
      health_score: calculate_agent_health_score(agent, time_range),
      performance: {
        success_rate: calculate_agent_success_rate(recent_executions),
        avg_response_time: calculate_agent_avg_response_time(recent_executions),
        throughput: calculate_agent_throughput(recent_executions, time_range),
        error_rate: calculate_agent_error_rate(recent_executions)
      },
      usage: {
        executions_count: recent_executions.count,
        total_tokens: recent_executions.sum { |e| e.result&.dig('tokens_used') || 0 },
        total_cost: recent_executions.sum { |e| e.result&.dig('cost') || 0 }
      },
      executions: {
        running: recent_executions.where(status: 'running').count,
        completed: recent_executions.where(status: 'completed').count,
        failed: recent_executions.where(status: 'failed').count,
        cancelled: recent_executions.where(status: 'cancelled').count
      },
      provider_distribution: get_agent_provider_distribution(recent_executions),
      alerts: get_agent_alerts(agent),
      last_execution: recent_executions.maximum(:created_at)&.iso8601,
      created_at: agent.created_at.iso8601,
      updated_at: agent.updated_at.iso8601
    }
  end

  def get_agents_summary
    agents = get_monitored_agents
    total_agents = agents.count

    {
      total_count: total_agents,
      active: agents.where(status: 'active').count,
      inactive: agents.where(status: 'inactive').count,
      healthy: agents.count { |a| calculate_agent_health_score(a, 1.hour) >= 80 },
      degraded: agents.count { |a| (50..79).include?(calculate_agent_health_score(a, 1.hour)) },
      unhealthy: agents.count { |a| calculate_agent_health_score(a, 1.hour) < 50 },
      recent_executions: get_agents_recent_executions_summary,
      active_alerts: get_agents_active_alerts_count
    }
  end

  # Workflow Monitoring
  def get_all_workflows_metrics(time_range: 1.hour)
    workflows = get_monitored_workflows

    workflows.map do |workflow|
      get_workflow_detailed_metrics(workflow, time_range: time_range)
    end
  end

  def get_workflow_detailed_metrics(workflow, time_range: 1.hour)
    recent_runs = workflow.ai_workflow_runs
                          .where('created_at > ?', Time.current - time_range)

    {
      id: workflow.id,
      name: workflow.name,
      status: workflow.status,
      version: workflow.version,
      health_score: calculate_workflow_health_score(workflow, time_range),
      performance: {
        success_rate: calculate_workflow_success_rate(recent_runs),
        avg_execution_time: calculate_workflow_avg_execution_time(recent_runs),
        throughput: calculate_workflow_throughput(recent_runs, time_range),
        failure_rate: calculate_workflow_failure_rate(recent_runs)
      },
      usage: {
        runs_count: recent_runs.count,
        nodes_executed: recent_runs.joins(:ai_workflow_node_executions).count,
        total_cost: recent_runs.sum(&:cost) || 0
      },
      runs: {
        running: recent_runs.where(status: 'running').count,
        completed: recent_runs.where(status: 'completed').count,
        failed: recent_runs.where(status: 'failed').count,
        cancelled: recent_runs.where(status: 'cancelled').count
      },
      nodes: {
        total_nodes: workflow.ai_workflow_nodes.count,
        node_performance: get_workflow_nodes_performance(workflow, time_range)
      },
      triggers: get_workflow_triggers_summary(workflow, time_range),
      alerts: get_workflow_alerts(workflow),
      last_run: recent_runs.maximum(:created_at)&.iso8601,
      created_at: workflow.created_at.iso8601,
      updated_at: workflow.updated_at.iso8601
    }
  end

  def get_workflows_summary
    workflows = get_monitored_workflows
    total_workflows = workflows.count

    {
      total_count: total_workflows,
      active: workflows.where(status: 'active').count,
      draft: workflows.where(status: 'draft').count,
      inactive: workflows.where(status: 'inactive').count,
      healthy: workflows.count { |w| calculate_workflow_health_score(w, 1.hour) >= 80 },
      degraded: workflows.count { |w| (50..79).include?(calculate_workflow_health_score(w, 1.hour)) },
      unhealthy: workflows.count { |w| calculate_workflow_health_score(w, 1.hour) < 50 },
      recent_runs: get_workflows_recent_runs_summary,
      active_alerts: get_workflows_active_alerts_count
    }
  end

  # Conversation Monitoring
  def get_all_conversations_metrics(time_range: 1.hour)
    conversations = get_monitored_conversations(time_range)

    conversations.map do |conversation|
      get_conversation_detailed_metrics(conversation, time_range: time_range)
    end
  end

  def get_conversation_detailed_metrics(conversation, time_range: 1.hour)
    recent_messages = conversation.ai_messages
                                  .where('created_at > ?', Time.current - time_range)

    {
      id: conversation.id,
      title: conversation.title,
      status: conversation.status,
      health_score: calculate_conversation_health_score(conversation, time_range),
      performance: {
        avg_response_time: calculate_conversation_avg_response_time(recent_messages),
        message_throughput: calculate_conversation_throughput(recent_messages, time_range),
        success_rate: calculate_conversation_success_rate(recent_messages)
      },
      usage: {
        messages_count: recent_messages.count,
        total_tokens: recent_messages.sum(&:token_count) || 0,
        total_cost: recent_messages.sum(&:cost) || 0
      },
      participants: {
        human_messages: recent_messages.where(role: 'user').count,
        ai_messages: recent_messages.where(role: 'assistant').count,
        system_messages: recent_messages.where(role: 'system').count
      },
      agent_usage: get_conversation_agent_usage(recent_messages),
      alerts: get_conversation_alerts(conversation),
      last_activity: recent_messages.maximum(:created_at)&.iso8601,
      created_at: conversation.created_at.iso8601,
      updated_at: conversation.updated_at.iso8601
    }
  end

  def get_conversations_summary
    conversations = get_monitored_conversations(24.hours)
    active_conversations = conversations.where('updated_at > ?', 1.hour.ago)

    {
      total_count: conversations.count,
      active_count: active_conversations.count,
      recent_activity: conversations.where('updated_at > ?', 24.hours.ago).count,
      avg_messages_per_conversation: conversations.joins(:ai_messages).group('ai_conversations.id').average('ai_messages.id').values.sum / conversations.count.to_f,
      healthy: conversations.count { |c| calculate_conversation_health_score(c, 1.hour) >= 80 },
      active_alerts: get_conversations_active_alerts_count
    }
  end

  # Cost Analysis
  def get_cost_analysis(time_range: 24.hours, breakdown: 'provider')
    case breakdown
    when 'provider'
      get_cost_by_provider(time_range)
    when 'agent'
      get_cost_by_agent(time_range)
    when 'workflow'
      get_cost_by_workflow(time_range)
    when 'conversation'
      get_cost_by_conversation(time_range)
    else
      get_cost_overview(time_range)
    end
  end

  # Performance Metrics
  def get_performance_metrics(time_range: 1.hour, metric_type: 'response_time')
    case metric_type
    when 'response_time'
      get_response_time_metrics(time_range)
    when 'success_rate'
      get_success_rate_metrics(time_range)
    when 'throughput'
      get_throughput_metrics(time_range)
    when 'resource_usage'
      get_resource_usage_metrics(time_range)
    else
      get_performance_overview(time_range)
    end
  end

  # Resource Utilization
  def get_resource_utilization
    {
      system: {
        cpu_usage: get_system_cpu_usage,
        memory_usage: get_system_memory_usage,
        disk_usage: get_system_disk_usage,
        network_usage: get_system_network_usage
      },
      database: {
        connection_pool: get_database_connection_pool_status,
        query_performance: get_database_query_performance,
        storage_usage: get_database_storage_usage
      },
      redis: {
        memory_usage: get_redis_memory_usage,
        connection_count: get_redis_connection_count,
        hit_rate: get_redis_hit_rate
      },
      sidekiq: {
        queue_sizes: get_sidekiq_queue_sizes,
        worker_utilization: get_sidekiq_worker_utilization,
        failed_jobs: get_sidekiq_failed_jobs_count
      },
      actioncable: {
        connection_count: get_actioncable_connection_count,
        subscription_count: get_actioncable_subscription_count,
        message_throughput: get_actioncable_message_throughput
      }
    }
  end

  # Alerts Management
  def get_alerts(filters: {}, page: 1, per_page: 50)
    alerts = build_alerts_query(filters)

    total_count = alerts.count
    offset = (page - 1) * per_page

    paginated_alerts = alerts.limit(per_page).offset(offset).order(created_at: :desc)

    {
      alerts: paginated_alerts.map { |alert| format_alert_data(alert) },
      total_count: total_count,
      summary: get_alerts_summary(filters)
    }
  end

  def acknowledge_alert(alert_id, user_id, note = nil)
    alert = find_alert(alert_id)
    return false unless alert

    alert.update!(
      acknowledged: true,
      acknowledged_at: Time.current,
      acknowledged_by: user_id,
      acknowledgment_note: note
    )

    broadcast_alert_acknowledgment(alert)
    true
  rescue StandardError => e
    @logger.error "Failed to acknowledge alert #{alert_id}: #{e.message}"
    false
  end

  def resolve_alert(alert_id, user_id, resolution_note = nil)
    alert = find_alert(alert_id)
    return false unless alert

    alert.update!(
      resolved: true,
      resolved_at: Time.current,
      resolved_by: user_id,
      resolution_note: resolution_note
    )

    broadcast_alert_resolution(alert)
    true
  rescue StandardError => e
    @logger.error "Failed to resolve alert #{alert_id}: #{e.message}"
    false
  end

  # Component Testing
  def test_component(component_type:, component_id:, test_params: {})
    case component_type
    when 'provider'
      test_provider_component(component_id, test_params)
    when 'agent'
      test_agent_component(component_id, test_params)
    when 'workflow'
      test_workflow_component(component_id, test_params)
    else
      raise ArgumentError, "Unknown component type: #{component_type}"
    end
  end

  private

  # Helper methods for various calculations and data retrieval
  def get_monitored_providers
    @account ? @account.ai_providers.active : AiProvider.active
  end

  def get_monitored_agents
    @account ? @account.ai_agents : AiAgent.where(account: nil)
  end

  def get_monitored_workflows
    @account ? @account.ai_workflows : AiWorkflow.where(account: nil)
  end

  def get_monitored_conversations(time_range = 24.hours)
    scope = @account ? @account.ai_conversations : AiConversation.where(account: nil)
    scope.where('updated_at > ?', Time.current - time_range)
  end

  def calculate_system_health_score
    providers_score = calculate_providers_health_score
    agents_score = calculate_agents_health_score
    workflows_score = calculate_workflows_health_score
    infrastructure_score = calculate_infrastructure_health_score

    # Weighted average
    (providers_score * 0.3 + agents_score * 0.25 + workflows_score * 0.25 + infrastructure_score * 0.2).round(2)
  end

  def determine_system_status
    score = calculate_system_health_score
    case score
    when 90..100
      'excellent'
    when 80..89
      'good'
    when 70..79
      'fair'
    when 50..69
      'degraded'
    else
      'critical'
    end
  end

  # Additional helper methods would be implemented here...
  # This is a comprehensive service that would need many more supporting methods
  # for metrics calculations, data aggregation, and component-specific monitoring

  def get_system_overview
    {
      total_providers: get_monitored_providers.count,
      total_agents: get_monitored_agents.count,
      total_workflows: get_monitored_workflows.count,
      active_conversations: get_monitored_conversations(1.hour).count,
      system_uptime: get_system_uptime,
      last_updated: Time.current.iso8601
    }
  end

  def get_system_metrics(time_range)
    {
      executions_total: get_total_executions(time_range),
      success_rate: get_system_success_rate(time_range),
      avg_response_time: get_system_avg_response_time(time_range),
      total_cost: get_total_cost(time_range),
      error_count: get_total_errors(time_range)
    }
  end

  # Placeholder implementations for metrics calculations
  # These would need to be implemented based on the actual data models and requirements

  def calculate_providers_health_score
    providers = get_monitored_providers
    return 100.0 if providers.empty?

    scores = providers.map { |p| calculate_provider_health_score(p, 1.hour) }
    scores.sum / scores.size.to_f
  end

  def calculate_agents_health_score
    agents = get_monitored_agents
    return 100.0 if agents.empty?

    scores = agents.map { |a| calculate_agent_health_score(a, 1.hour) }
    scores.sum / scores.size.to_f
  end

  def calculate_workflows_health_score
    workflows = get_monitored_workflows
    return 100.0 if workflows.empty?

    scores = workflows.map { |w| calculate_workflow_health_score(w, 1.hour) }
    scores.sum / scores.size.to_f
  end

  def calculate_infrastructure_health_score
    # Implementation would check system resources, database health, etc.
    85.0 # Placeholder
  end

  def calculate_provider_health_score(provider, time_range)
    # Implementation would calculate based on success rate, response time, circuit breaker state, etc.
    90.0 # Placeholder
  end

  def calculate_agent_health_score(agent, time_range)
    # Implementation would calculate based on execution success rate, response time, error count, etc.
    85.0 # Placeholder
  end

  def calculate_workflow_health_score(workflow, time_range)
    # Implementation would calculate based on run success rate, execution time, node failures, etc.
    88.0 # Placeholder
  end

  def calculate_conversation_health_score(conversation, time_range)
    # Implementation would calculate based on message success rate, response time, error rate, etc.
    92.0 # Placeholder
  end

  # Additional placeholder methods that would need full implementation
  def get_providers_dashboard_summary(time_range)
    { active: 5, healthy: 4, degraded: 1, unhealthy: 0 }
  end

  def get_agents_dashboard_summary(time_range)
    { active: 10, running_executions: 3, completed_today: 45, failed_today: 2 }
  end

  def get_workflows_dashboard_summary(time_range)
    { active: 8, running: 2, completed_today: 12, failed_today: 1 }
  end

  def get_conversations_dashboard_summary(time_range)
    { active: 15, messages_today: 150, avg_response_time: 1.2 }
  end

  def get_costs_dashboard_summary(time_range)
    { total_today: 25.50, by_provider: {}, trending: 'up' }
  end

  def get_alerts_dashboard_summary
    { active: 3, high_priority: 1, medium_priority: 2, low_priority: 0 }
  end

  def get_resources_dashboard_summary
    { cpu_usage: 45, memory_usage: 60, disk_usage: 30, healthy: true }
  end

  # More methods would be implemented here for full functionality...
end