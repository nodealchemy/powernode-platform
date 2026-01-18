# frozen_string_literal: true

class AiDebuggingService
  include ActiveModel::Model
  include ActiveModel::Attributes

  class DebuggingError < StandardError; end

  def initialize(account, execution_context = {})
    @account = account
    @execution_context = execution_context
    @logger = Rails.logger
    @redis = Redis.new(url: Rails.application.credentials.redis_url || "redis://localhost:6379")
  end

  # Generate comprehensive debugging report for failed execution
  def generate_debug_report(execution_id, execution_type = "agent")
    execution = find_execution(execution_id, execution_type)
    return nil unless execution

    report = {
      execution_info: build_execution_info(execution),
      system_state: capture_system_state,
      provider_diagnostics: generate_provider_diagnostics(execution),
      error_analysis: analyze_execution_errors(execution),
      performance_metrics: collect_performance_metrics(execution),
      recovery_suggestions: generate_recovery_suggestions(execution),
      troubleshooting_steps: generate_troubleshooting_steps(execution),
      related_incidents: find_related_incidents(execution),
      debug_logs: collect_debug_logs(execution),
      configuration_issues: detect_configuration_issues(execution)
    }

    # Store report for future reference
    store_debug_report(execution_id, report)

    report
  end

  # Real-time debugging session for active execution
  def start_debug_session(execution_id, execution_type = "agent")
    execution = find_execution(execution_id, execution_type)
    return nil unless execution

    session_id = SecureRandom.uuid
    debug_session = {
      session_id: session_id,
      execution_id: execution_id,
      execution_type: execution_type,
      started_at: Time.current.iso8601,
      status: "active",
      collected_data: []
    }

    store_debug_session(session_id, debug_session)

    # Start real-time monitoring
    monitor_execution_realtime(execution, session_id)

    session_id
  end

  # Collect debug session data
  def collect_debug_data(session_id, data_type, data)
    session = get_debug_session(session_id)
    return false unless session

    debug_entry = {
      timestamp: Time.current.iso8601,
      data_type: data_type,
      data: data,
      context: @execution_context
    }

    session["collected_data"] << debug_entry
    store_debug_session(session_id, session)

    true
  end

  # Get debug session status and data
  def get_debug_session_status(session_id)
    get_debug_session(session_id)
  end

  # End debug session and generate final report
  def end_debug_session(session_id)
    session = get_debug_session(session_id)
    return nil unless session

    session["status"] = "completed"
    session["ended_at"] = Time.current.iso8601
    session["final_report"] = compile_session_report(session)

    store_debug_session(session_id, session)
    cleanup_debug_session(session_id)

    session["final_report"]
  end

  # Analyze execution patterns for anomalies
  def analyze_execution_patterns(time_range = 24.hours)
    executions = get_recent_executions(time_range)

    {
      total_executions: executions.count,
      failure_patterns: detect_failure_patterns(executions),
      performance_anomalies: detect_performance_anomalies(executions),
      provider_issues: detect_provider_issues(executions),
      configuration_drifts: detect_configuration_drifts(executions),
      recommendations: generate_pattern_recommendations(executions)
    }
  end

  # Generate execution replay for debugging
  def generate_execution_replay(execution_id, execution_type = "agent")
    execution = find_execution(execution_id, execution_type)
    return nil unless execution

    replay_data = {
      execution_id: execution_id,
      execution_type: execution_type,
      original_input: extract_original_input(execution),
      execution_steps: reconstruct_execution_steps(execution),
      provider_interactions: extract_provider_interactions(execution),
      state_changes: extract_state_changes(execution),
      error_points: identify_error_points(execution),
      replay_instructions: generate_replay_instructions(execution)
    }

    store_execution_replay(execution_id, replay_data)
    replay_data
  end

  # Performance profiling for specific execution
  def profile_execution_performance(execution_id, execution_type = "agent")
    execution = find_execution(execution_id, execution_type)
    return nil unless execution

    {
      execution_timeline: build_execution_timeline(execution),
      bottlenecks: identify_performance_bottlenecks(execution),
      resource_usage: analyze_resource_usage(execution),
      network_analysis: analyze_network_performance(execution),
      optimization_suggestions: suggest_performance_optimizations(execution)
    }
  end

  private

  def find_execution(execution_id, execution_type)
    case execution_type
    when "agent"
      @account.ai_agent_executions.find_by(id: execution_id)
    when "workflow"
      @account.ai_workflows
              .joins(:ai_workflow_runs)
              .find_by(ai_workflow_runs: { id: execution_id })
              &.workflow_runs
              &.find_by(id: execution_id)
    else
      nil
    end
  end

  def build_execution_info(execution)
    base_info = {
      id: execution.id,
      status: execution.status,
      started_at: execution.started_at&.iso8601,
      completed_at: execution.completed_at&.iso8601,
      error_message: execution.error_message,
      execution_context: execution.execution_context || {}
    }

    if execution.respond_to?(:ai_agent)
      base_info.merge!({
        type: "agent_execution",
        agent_id: execution.ai_agent_id,
        agent_name: execution.agent.name,
        provider_id: execution.agent.ai_provider_id
      })
    else
      base_info.merge!({
        type: "workflow_execution",
        workflow_id: execution.ai_workflow_id,
        workflow_name: execution.workflow.name
      })
    end

    base_info
  end

  def capture_system_state
    {
      timestamp: Time.current.iso8601,
      active_executions: count_active_executions,
      provider_statuses: get_all_provider_statuses,
      system_load: get_system_load_metrics,
      circuit_breaker_states: get_circuit_breaker_states,
      queue_statuses: get_queue_statuses
    }
  end

  def generate_provider_diagnostics(execution)
    provider = get_execution_provider(execution)
    return {} unless provider

    circuit_breaker = AiProviderCircuitBreakerService.new(provider)
    load_balancer = AiProviderLoadBalancerService.new(@account)

    {
      provider_id: provider.id,
      provider_name: provider.name,
      provider_status: provider.status,
      circuit_state: circuit_breaker.circuit_state,
      circuit_stats: circuit_breaker.circuit_stats,
      load_stats: load_balancer.load_balancing_stats.dig(:providers)&.find { |p| p[:id] == provider.id },
      recent_failures: get_provider_recent_failures(provider),
      configuration: provider.configuration,
      credentials_status: provider.provider_credentials.active.exists?
    }
  end

  def analyze_execution_errors(execution)
    return {} unless execution.error_message

    error_analysis = {
      error_message: execution.error_message,
      error_classification: classify_error_type(execution.error_message),
      error_frequency: count_similar_errors(execution.error_message),
      error_pattern: detect_error_pattern(execution.error_message),
      potential_causes: identify_potential_causes(execution.error_message),
      similar_incidents: find_similar_error_incidents(execution.error_message)
    }

    # Add context-specific analysis
    if execution.respond_to?(:ai_agent)
      error_analysis[:agent_context] = analyze_agent_error_context(execution)
    else
      error_analysis[:workflow_context] = analyze_workflow_error_context(execution)
    end

    error_analysis
  end

  def collect_performance_metrics(execution)
    execution_time = if execution.started_at && execution.completed_at
                      (execution.completed_at - execution.started_at) * 1000
    else
                      nil
    end

    {
      execution_time_ms: execution_time,
      queue_time: calculate_queue_time(execution),
      processing_time: calculate_processing_time(execution),
      api_response_times: get_api_response_times(execution),
      memory_usage: get_memory_usage(execution),
      token_usage: get_token_usage(execution),
      cost_metrics: get_cost_metrics(execution)
    }
  end

  def generate_recovery_suggestions(execution)
    suggestions = []

    if execution.error_message
      error_type = classify_error_type(execution.error_message)
      suggestions.concat(get_error_type_suggestions(error_type))
    end

    if execution.respond_to?(:ai_agent)
      provider = execution.agent.provider
      suggestions.concat(get_provider_suggestions(provider))
    end

    suggestions.concat(get_general_suggestions(execution))
    suggestions.uniq
  end

  def generate_troubleshooting_steps(execution)
    [
      {
        step: 1,
        action: "Check provider status and credentials",
        details: "Verify that the AI provider is active and has valid credentials"
      },
      {
        step: 2,
        action: "Review error logs and patterns",
        details: "Examine the specific error message and look for similar incidents"
      },
      {
        step: 3,
        action: "Test provider connectivity",
        details: "Use the monitoring controller to test provider connectivity"
      },
      {
        step: 4,
        action: "Check resource limits and quotas",
        details: "Verify account limits and provider quota availability"
      },
      {
        step: 5,
        action: "Review execution configuration",
        details: "Validate input parameters and execution settings"
      }
    ]
  end

  def find_related_incidents(execution)
    # Find similar executions that failed
    similar_executions = if execution.respond_to?(:ai_agent)
                          find_similar_agent_executions(execution)
    else
                          find_similar_workflow_executions(execution)
    end

    similar_executions.limit(10).map do |similar|
      {
        id: similar.id,
        failed_at: similar.completed_at&.iso8601,
        error_message: similar.error_message,
        similarity_score: calculate_similarity_score(execution, similar)
      }
    end
  end

  def collect_debug_logs(execution)
    # This would collect relevant log entries
    # For now, return structured placeholder data
    {
      application_logs: [],
      provider_api_logs: [],
      worker_logs: [],
      system_logs: [],
      note: "Log collection would be implemented based on logging infrastructure"
    }
  end

  def detect_configuration_issues(execution)
    issues = []

    if execution.respond_to?(:ai_agent)
      agent = execution.agent
      provider = agent.provider

      # Check provider configuration
      unless provider.provider_credentials.active.exists?
        issues << {
          type: "missing_credentials",
          severity: "critical",
          description: "No active credentials found for provider"
        }
      end

      # Check agent configuration
      if agent.configuration.blank?
        issues << {
          type: "missing_agent_config",
          severity: "warning",
          description: "Agent has no configuration specified"
        }
      end
    end

    issues
  end

  def store_debug_report(execution_id, report)
    key = "debug_report:#{@account.id}:#{execution_id}"
    @redis.setex(key, 7.days, report.to_json)
  end

  def store_debug_session(session_id, session_data)
    key = "debug_session:#{@account.id}:#{session_id}"
    @redis.setex(key, 1.hour, session_data.to_json)
  end

  def get_debug_session(session_id)
    key = "debug_session:#{@account.id}:#{session_id}"
    session_json = @redis.get(key)
    session_json ? JSON.parse(session_json) : nil
  end

  def cleanup_debug_session(session_id)
    # Archive completed session data
    key = "debug_session:#{@account.id}:#{session_id}"
    archive_key = "debug_session_archive:#{@account.id}:#{session_id}"

    session_data = @redis.get(key)
    @redis.setex(archive_key, 30.days, session_data) if session_data
    @redis.del(key)
  end

  # Helper methods for various analysis tasks
  def classify_error_type(error_message)
    message = error_message.downcase

    case message
    when /rate limit|429|too many requests/
      "rate_limit"
    when /timeout|timed out/
      "timeout"
    when /unauthorized|401|authentication/
      "authentication"
    when /quota|billing|payment/
      "quota_exceeded"
    when /validation|400|bad request/
      "validation"
    when /server error|500|502|503|504/
      "server_error"
    else
      "unknown"
    end
  end

  def count_active_executions
    @account.ai_agent_executions.where(status: %w[pending running]).count
  end

  def get_all_provider_statuses
    @account.ai_providers.active.map do |provider|
      circuit_breaker = AiProviderCircuitBreakerService.new(provider)
      {
        id: provider.id,
        name: provider.name,
        status: provider.status,
        circuit_state: circuit_breaker.circuit_state
      }
    end
  end

  def get_system_load_metrics
    # Placeholder for system metrics
    {
      cpu_usage: 0.0,
      memory_usage: 0.0,
      active_connections: 0,
      queue_size: 0
    }
  end

  def get_circuit_breaker_states
    @account.ai_providers.active.map do |provider|
      circuit_breaker = AiProviderCircuitBreakerService.new(provider)
      {
        provider_id: provider.id,
        state: circuit_breaker.circuit_state,
        failure_count: circuit_breaker.send(:get_failure_count),
        last_failure: circuit_breaker.send(:get_last_failure_time)
      }
    end
  end

  def get_queue_statuses
    # Placeholder for queue status information
    {
      default: { size: 0, latency: 0 },
      ai_processing: { size: 0, latency: 0 }
    }
  end

  # Additional helper methods for debugging functionality
  def monitor_execution_realtime(execution, session_id)
    # Placeholder for real-time monitoring implementation
  end

  def compile_session_report(session)
    # Compile final report from session data
    {
      session_id: session["session_id"],
      duration: Time.current - Time.parse(session["started_at"]),
      data_points: session["collected_data"].size,
      summary: "Debug session completed successfully"
    }
  end

  def get_recent_executions(time_range)
    @account.ai_agent_executions
            .where(created_at: time_range.ago..Time.current)
            .order(created_at: :desc)
  end

  def detect_failure_patterns(executions)
    failed_executions = executions.select { |e| e.status == "failed" }
    error_types = failed_executions.map { |e| classify_error_type(e.error_message || "") }
    error_types.tally.map { |type, count| "#{type}: #{count} occurrences" }
  end

  def detect_performance_anomalies(executions)
    # Simple anomaly detection based on execution times
    times = executions.filter_map(&:duration_ms).compact
    return [] if times.empty?

    avg_time = times.sum / times.size
    slow_executions = executions.select { |e| e.duration_ms && e.duration_ms > avg_time * 2 }
    [ "Found #{slow_executions.size} executions significantly slower than average" ]
  end

  def detect_provider_issues(executions)
    # Group by provider and check failure rates
    provider_stats = executions.group_by(&:ai_provider_id)
                              .transform_values do |execs|
      failed = execs.count { |e| e.status == "failed" }
      total = execs.size
      { failed: failed, total: total, rate: total > 0 ? (failed.to_f / total * 100).round(2) : 0 }
    end

    provider_stats.filter_map do |provider_id, stats|
      "Provider #{provider_id}: #{stats[:rate]}% failure rate" if stats[:rate] > 10
    end
  end

  def detect_configuration_drifts(executions)
    # Placeholder for configuration drift detection
    []
  end

  def generate_pattern_recommendations(executions)
    recommendations = []

    # Check for high failure rates
    failed_rate = executions.count { |e| e.status == "failed" }.to_f / executions.size * 100
    if failed_rate > 20
      recommendations << "Consider implementing circuit breaker pattern"
      recommendations << "Review error handling and retry strategies"
    end

    recommendations
  end

  def extract_original_input(execution)
    execution.input_parameters || {}
  end

  def reconstruct_execution_steps(execution)
    # Placeholder for execution step reconstruction
    [ { step: 1, action: "Execution started", timestamp: execution.started_at&.iso8601 } ]
  end

  def extract_provider_interactions(execution)
    # Placeholder for provider interaction extraction
    [ { interaction: "API call", timestamp: execution.started_at&.iso8601 } ]
  end

  def extract_state_changes(execution)
    # Placeholder for state change extraction
    [ { from: "pending", to: execution.status, timestamp: execution.completed_at&.iso8601 } ]
  end

  def identify_error_points(execution)
    return [] unless execution.error_message
    [ { error: execution.error_message, timestamp: execution.completed_at&.iso8601 } ]
  end

  def generate_replay_instructions(execution)
    # Generate instructions for replaying the execution
    [ "1. Check provider credentials", "2. Verify input parameters", "3. Retry execution" ]
  end

  def store_execution_replay(execution_id, replay_data)
    key = "execution_replay:#{@account.id}:#{execution_id}"
    @redis.setex(key, 7.days, replay_data.to_json)
  end

  def build_execution_timeline(execution)
    timeline = []
    timeline << { event: "created", timestamp: execution.created_at.iso8601 }
    timeline << { event: "started", timestamp: execution.started_at.iso8601 } if execution.started_at
    timeline << { event: "completed", timestamp: execution.completed_at.iso8601 } if execution.completed_at
    timeline
  end

  def identify_performance_bottlenecks(execution)
    bottlenecks = []
    if execution.duration_ms && execution.duration_ms > 10000
      bottlenecks << "Execution time exceeds 10 seconds"
    end
    bottlenecks
  end

  def analyze_resource_usage(execution)
    # Placeholder for resource usage analysis
    { memory: "Unknown", cpu: "Unknown", network: "Unknown" }
  end

  def analyze_network_performance(execution)
    # Placeholder for network performance analysis
    { latency: "Unknown", throughput: "Unknown" }
  end

  def suggest_performance_optimizations(execution)
    suggestions = []
    if execution.duration_ms && execution.duration_ms > 5000
      suggestions << "Consider using streaming responses for long operations"
    end
    suggestions
  end
end
