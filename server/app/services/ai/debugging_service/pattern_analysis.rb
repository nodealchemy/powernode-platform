# frozen_string_literal: true

class Ai::DebuggingService
  module PatternAnalysis
    extend ActiveSupport::Concern

    private

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
        circuit_breaker = Ai::ProviderCircuitBreakerService.new(provider)
        {
          id: provider.id,
          name: provider.name,
          status: provider.status,
          circuit_state: circuit_breaker.circuit_state
        }
      end
    end

    def get_system_load_metrics
      load_avg = if File.exist?("/proc/loadavg")
                   parts = File.read("/proc/loadavg").split
                   { load_1m: parts[0].to_f, load_5m: parts[1].to_f, load_15m: parts[2].to_f }
                 else
                   { load_1m: 0.0, load_5m: 0.0, load_15m: 0.0 }
                 end

      memory = if File.exist?("/proc/meminfo")
                 meminfo = File.read("/proc/meminfo")
                 total = meminfo[/MemTotal:\s+(\d+)/, 1].to_f
                 available = meminfo[/MemAvailable:\s+(\d+)/, 1].to_f
                 total.positive? ? ((1 - available / total) * 100).round(1) : 0.0
               else
                 0.0
               end

      {
        cpu_usage: load_avg[:load_1m],
        memory_usage: memory,
        active_connections: count_active_executions,
        queue_size: @account.ai_agent_executions.where(status: "pending").count
      }
    end

    def get_circuit_breaker_states
      @account.ai_providers.active.map do |provider|
        circuit_breaker = Ai::ProviderCircuitBreakerService.new(provider)
        {
          provider_id: provider.id,
          state: circuit_breaker.circuit_state,
          failure_count: circuit_breaker.send(:get_failure_count),
          last_failure: circuit_breaker.send(:get_last_failure_time)
        }
      end
    end

    def get_queue_statuses
      pending = @account.ai_agent_executions.where(status: "pending")
      running = @account.ai_agent_executions.where(status: "running")

      avg_wait = pending.where.not(created_at: nil)
                        .pluck(:created_at)
                        .map { |t| (Time.current - t).round(2) }
                        .then { |waits| waits.any? ? (waits.sum / waits.size).round(2) : 0 }

      {
        pending: { size: pending.count, avg_wait_seconds: avg_wait },
        running: { size: running.count }
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
      drifts = []
      agent_ids = executions.map(&:ai_agent_id).uniq.compact
      agent_ids.each do |agent_id|
        agent = Ai::Agent.find_by(id: agent_id)
        next unless agent

        agent_execs = executions.select { |e| e.ai_agent_id == agent_id }
        configs = agent_execs.filter_map { |e| e.input_parameters&.dig("configuration") }.uniq
        if configs.size > 1
          drifts << "Agent '#{agent.name}' used #{configs.size} different configurations across #{agent_execs.size} executions"
        end
      end
      drifts
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
  end
end
