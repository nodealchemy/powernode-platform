# frozen_string_literal: true

module Ai
  class SelfHealingMonitorJob < ApplicationJob
    queue_as :default

    STUCK_WORKFLOW_TIMEOUT = 30.minutes
    DEGRADED_ERROR_THRESHOLD = 50 # percent

    def perform
      return unless Shared::FeatureFlagService.enabled?(:self_healing_remediation)

      Account.find_each do |account|
        check_stuck_workflows(account)
        check_degraded_providers(account)
        check_orphaned_executions(account)
        check_cross_system_anomalies(account)
      rescue => e
        Rails.logger.error "[SelfHealingMonitor] Error for account #{account.id}: #{e.message}"
      end
    end

    private

    def check_stuck_workflows(account)
      stuck_runs = Ai::WorkflowRun.where(account: account)
                                   .where(status: "running")
                                   .where("started_at < ?", STUCK_WORKFLOW_TIMEOUT.ago)

      stuck_runs.find_each do |run|
        Ai::SelfHealing::RemediationDispatcher.dispatch(
          account: account,
          trigger_source: "SelfHealingMonitor",
          trigger_event: "stuck_execution",
          context: {
            execution_id: run.id,
            execution_type: "WorkflowRun",
            status: run.status,
            started_at: run.started_at&.iso8601,
            message: "Workflow run #{run.id} stuck in running state for over #{STUCK_WORKFLOW_TIMEOUT.inspect}"
          }
        )
      end
    rescue => e
      Rails.logger.error "[SelfHealingMonitor] Stuck workflow check failed: #{e.message}"
    end

    def check_degraded_providers(account)
      Ai::Provider.find_each do |provider|
        breaker = Ai::ProviderCircuitBreakerService.new(provider)
        stats = breaker.circuit_stats

        next unless stats[:state].to_s == "closed"
        next unless stats[:failure_count].to_i > 3

        total = stats[:failure_count].to_i + stats[:success_count].to_i
        next if total.zero?

        error_rate = (stats[:failure_count].to_f / total * 100).round(1)
        next unless error_rate >= DEGRADED_ERROR_THRESHOLD

        Ai::SelfHealing::RemediationDispatcher.dispatch(
          account: account,
          trigger_source: "SelfHealingMonitor",
          trigger_event: "repeated_failures",
          context: {
            provider_id: provider.id,
            service_type: "provider",
            error_rate: error_rate,
            severity: "warning",
            message: "Provider #{provider.name} degraded: #{error_rate}% error rate"
          }
        )
      end
    rescue => e
      Rails.logger.error "[SelfHealingMonitor] Degraded provider check failed: #{e.message}"
    end

    def check_orphaned_executions(account)
      # Ralph iterations stuck in running
      Ai::RalphIteration.joins(:ralph_loop)
                         .where(ai_ralph_loops: { account_id: account.id })
                         .where(status: "running")
                         .where("ai_ralph_iterations.started_at < ?", 1.hour.ago)
                         .find_each do |iteration|
        iteration.update!(status: "failed", error_message: "Orphaned execution detected by monitor")
      end

      # Agent executions stuck in running
      Ai::AgentExecution.where(account: account)
                        .where(status: "running")
                        .where("started_at < ?", 1.hour.ago)
                        .find_each do |execution|
        execution.update!(status: "failed", error_message: "Orphaned execution detected by monitor")
      end
    rescue => e
      Rails.logger.error "[SelfHealingMonitor] Orphaned execution check failed: #{e.message}"
    end

    def check_cross_system_anomalies(account)
      correlator = Ai::SelfHealing::CrossSystemCorrelator.new(account: account)
      correlations = correlator.correlate_failures(time_range: 30.minutes)

      high_confidence = correlations.select { |c| c[:confidence] >= 0.6 }
      return if high_confidence.empty?

      Ai::SelfHealing::RemediationDispatcher.dispatch(
        account: account,
        trigger_source: "SelfHealingMonitor",
        trigger_event: "repeated_failures",
        context: {
          severity: "info",
          correlation_count: high_confidence.count,
          message: "Cross-system anomalies detected: #{high_confidence.count} correlations",
          top_correlation: high_confidence.first[:suggested_cause]
        }
      )
    rescue => e
      Rails.logger.error "[SelfHealingMonitor] Cross-system anomaly check failed: #{e.message}"
    end
  end
end
