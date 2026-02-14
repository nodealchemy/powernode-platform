# frozen_string_literal: true

class Ai::DebuggingService
  module ReportGeneration
    extend ActiveSupport::Concern

    private

    def build_execution_info(execution)
      base_info = {
        id: execution.id,
        status: execution.status,
        started_at: execution.started_at&.iso8601,
        completed_at: execution.completed_at&.iso8601,
        error_message: execution.error_message,
        execution_context: execution.execution_context || {}
      }

      if execution.respond_to?(:agent)
        base_info.merge!({
          type: "agent_execution",
          agent_id: execution.ai_agent_id,
          agent_name: execution.agent.name,
          provider_id: execution.ai_provider_id
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

      circuit_breaker = Ai::ProviderCircuitBreakerService.new(provider)
      load_balancer = Ai::ProviderLoadBalancerService.new(@account)

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
      if execution.respond_to?(:agent)
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

      if execution.respond_to?(:agent)
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
      similar_executions = if execution.respond_to?(:agent)
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
      # Collect relevant log entries from available sources
      {
        application_logs: fetch_application_logs(execution),
        provider_api_logs: fetch_provider_api_logs(execution),
        worker_logs: fetch_worker_logs(execution),
        system_logs: []
      }
    end

    def fetch_application_logs(execution)
      # Fetch from workflow run logs if available
      return [] unless execution.respond_to?(:workflow_run) && execution.workflow_run

      execution.workflow_run.workflow_run_logs
        .where(created_at: (execution.started_at || 1.hour.ago)..Time.current)
        .order(created_at: :desc)
        .limit(50)
        .map do |log|
          {
            timestamp: log.created_at.iso8601,
            level: log.log_level,
            message: log.message,
            context: log.context_data
          }
        end
    rescue StandardError
      []
    end

    def fetch_provider_api_logs(execution)
      # Fetch from AI API logs if available
      return [] unless defined?(Ai::ApiLog) && Ai::ApiLog.table_exists?

      Ai::ApiLog
        .where(execution_id: execution.id)
        .order(created_at: :desc)
        .limit(20)
        .map do |log|
          {
            timestamp: log.created_at.iso8601,
            provider: log.provider_name,
            request_type: log.request_type,
            status: log.status,
            duration_ms: log.duration_ms,
            error: log.error_message
          }
        end
    rescue StandardError
      []
    end

    def fetch_worker_logs(execution)
      # Fetch from Sidekiq job logs if execution has a job ID
      return [] unless execution.respond_to?(:job_id) && execution.job_id.present?

      cache_key = "job_logs:#{execution.job_id}"
      cached_logs = @redis.lrange(cache_key, 0, 50)

      cached_logs.map do |log_json|
        JSON.parse(log_json, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end.compact
    rescue StandardError
      []
    end

    def detect_configuration_issues(execution)
      issues = []

      if execution.respond_to?(:agent)
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
  end
end
