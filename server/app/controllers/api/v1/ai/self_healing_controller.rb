# frozen_string_literal: true

module Api
  module V1
    module Ai
      class SelfHealingController < ApplicationController
        before_action :validate_permissions

        # GET /api/v1/ai/self_healing/remediation_logs
        def remediation_logs
          logs = ::Ai::RemediationLog.by_account(current_user.account_id)
                                      .recent(params[:limit]&.to_i || 50)

          logs = logs.by_action_type(params[:action_type]) if params[:action_type].present?

          render_success(
            remediation_logs: logs.map { |log| remediation_log_json(log) },
            health_summary: build_health_summary
          )
        end

        # GET /api/v1/ai/self_healing/health_summary
        def health_summary
          render_success(build_health_summary)
        end

        # GET /api/v1/ai/self_healing/correlations
        def correlations
          correlator = ::Ai::SelfHealing::CrossSystemCorrelator.new(account: current_user.account)
          time_range = (params[:time_range]&.to_i || 3600).seconds

          render_success(
            correlations: correlator.correlate_failures(time_range: time_range),
            devops_health: correlator.devops_health,
            timestamp: Time.current.iso8601
          )
        end

        private

        def validate_permissions
          require_permission("ai.monitoring.read")
        end

        def build_health_summary
          account_id = current_user.account_id
          logs_1h = ::Ai::RemediationLog.by_account(account_id).in_last_hour
          total_1h = logs_1h.count
          success_1h = logs_1h.successful.count

          {
            overall_status: determine_status(total_1h, success_1h),
            remediation_count_1h: total_1h,
            success_rate: total_1h > 0 ? (success_1h.to_f / total_1h * 100).round(1) : 100.0,
            active_circuit_breakers: count_open_circuit_breakers,
            feature_flag_enabled: Shared::FeatureFlagService.enabled?(:self_healing_remediation)
          }
        end

        def determine_status(total, successes)
          return "healthy" if total.zero?

          rate = successes.to_f / total
          if rate >= 0.8
            "healthy"
          elsif rate >= 0.5
            "degraded"
          else
            "critical"
          end
        end

        def count_open_circuit_breakers
          ::Ai::ProviderCircuitBreakerService.all_provider_stats.count { |s| s[:state].to_s == "open" }
        rescue StandardError
          0
        end

        def remediation_log_json(log)
          {
            id: log.id,
            trigger_source: log.trigger_source,
            trigger_event: log.trigger_event,
            action_type: log.action_type,
            result: log.result,
            result_message: log.result_message,
            executed_at: log.executed_at&.iso8601,
            before_state: log.before_state,
            after_state: log.after_state
          }
        end
      end
    end
  end
end
