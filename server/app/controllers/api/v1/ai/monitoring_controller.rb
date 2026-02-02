# frozen_string_literal: true

# Consolidated Monitoring Controller - Phase 3 Controller Consolidation
#
# This controller consolidates monitoring-related controllers into a single
# RESTful resource controller following the AI Orchestration Redesign pattern.
#
# Consolidates:
# - MonitoringController (status, health, metrics, alerts)
# - CircuitBreakersController (circuit breaker management)
# - AiHealthController (comprehensive health checks)
#
# Architecture:
# - Primary resource: Monitoring Dashboard
# - Integrates with Monitoring::UnifiedService (Phase 1)
# - Circuit breaker management
# - Real-time metrics broadcasting
# - Comprehensive health checking
#
module Api
  module V1
    module Ai
      class MonitoringController < ApplicationController
        include AuditLogging

        before_action :validate_permissions
        before_action :set_time_range, only: [ :dashboard, :metrics, :health ]
        before_action :set_components, only: [ :dashboard, :metrics ]

        # =============================================================================
        # DASHBOARD & METRICS
        # =============================================================================

        # GET /api/v1/ai/monitoring/dashboard
        def dashboard
          account = current_account
          service = Monitoring::UnifiedService.new(account: account)
          dashboard_data = service.get_dashboard(time_range: @time_range, components: @components)

          render_success(dashboard: dashboard_data, generated_at: Time.current.iso8601)
          log_audit_event("ai.monitoring.dashboard", account) if account
        end

        # GET /api/v1/ai/monitoring/metrics
        def metrics
          service = Monitoring::UnifiedService.new(account: current_user.account)
          metrics_data = @components.each_with_object({}) do |component, hash|
            hash[component] = service.collect_component_metrics(component, @time_range)
          end

          render_success(metrics: metrics_data, time_range_seconds: @time_range.to_i, timestamp: Time.current.iso8601)
        end

        # GET /api/v1/ai/monitoring/overview
        def overview
          service = Monitoring::UnifiedService.new(account: current_user.account)
          overview_data = service.get_system_overview
          health_score = service.calculate_health_score

          render_success(
            overview: overview_data,
            health_score: health_score,
            health_status: health_service.determine_health_status(health_score),
            timestamp: Time.current.iso8601
          )
        end

        # =============================================================================
        # HEALTH CHECKS
        # =============================================================================

        # GET /api/v1/ai/monitoring/health
        def health
          health_data = health_service.comprehensive_health_check(time_range: @time_range)

          render_success(health_data)
          log_audit_event("ai.monitoring.health_check", current_user.account,
            health_score: health_data[:health_score],
            status: health_data[:status]
          )
        end

        # GET /api/v1/ai/monitoring/health/detailed
        def health_detailed
          render_success(health_service.detailed_health)
        end

        # GET /api/v1/ai/monitoring/health/connectivity
        def health_connectivity
          render_success(health_service.connectivity_check)
        end

        # =============================================================================
        # ALERTS
        # =============================================================================

        # GET /api/v1/ai/monitoring/alerts
        def alerts
          service = Monitoring::UnifiedService.new(account: current_user.account)
          filters = { severity: params[:severity], type: params[:alert_type], status: params[:status] || "active" }.compact
          alerts_data = service.get_alerts(filters)

          render_success(alerts: alerts_data, timestamp: Time.current.iso8601)
          log_audit_event("ai.monitoring.alerts_view", current_user.account, filters: filters, alert_count: alerts_data[:total_alerts])
        end

        # POST /api/v1/ai/monitoring/alerts/check
        def alerts_check
          service = Monitoring::UnifiedService.new(account: current_user.account)
          triggered_alerts = service.check_and_trigger_alerts

          render_success(alerts_checked: true, triggered_alerts: triggered_alerts, count: triggered_alerts.count, timestamp: Time.current.iso8601)
          log_audit_event("ai.monitoring.alerts_check", current_user.account, triggered_count: triggered_alerts.count)
        end

        # =============================================================================
        # CIRCUIT BREAKERS
        # =============================================================================

        # GET /api/v1/ai/monitoring/circuit_breakers
        def circuit_breakers_index
          states = ::Ai::WorkflowCircuitBreakerManager.all_states
          summary = ::Ai::WorkflowCircuitBreakerManager.health_summary

          render_success(circuit_breakers: states, summary: summary, timestamp: Time.current.iso8601)
        end

        # GET /api/v1/ai/monitoring/circuit_breakers/:service_name
        def circuit_breaker_show
          breaker = ::Ai::WorkflowCircuitBreakerManager.get_breaker(params[:service_name])

          if breaker
            render_success(service_name: params[:service_name], stats: breaker.stats, timestamp: Time.current.iso8601)
          else
            render_error("Circuit breaker not found", status: :not_found)
          end
        end

        # POST /api/v1/ai/monitoring/circuit_breakers/:service_name/reset
        def circuit_breaker_reset
          breaker = ::Ai::WorkflowCircuitBreakerManager.get_or_create_breaker(params[:service_name])
          breaker.reset!

          render_success(message: "Circuit breaker reset for #{params[:service_name]}", service_name: params[:service_name], state: breaker.stats)
          log_audit_event("ai.monitoring.circuit_breaker.reset", current_user.account, service_name: params[:service_name])
        end

        # POST /api/v1/ai/monitoring/circuit_breakers/:service_name/open
        def circuit_breaker_open
          breaker = ::Ai::WorkflowCircuitBreakerManager.get_or_create_breaker(params[:service_name])
          breaker.open!

          render_success(message: "Circuit breaker opened for #{params[:service_name]}", service_name: params[:service_name], state: breaker.stats)
          log_audit_event("ai.monitoring.circuit_breaker.open", current_user.account, service_name: params[:service_name])
        end

        # POST /api/v1/ai/monitoring/circuit_breakers/:service_name/close
        def circuit_breaker_close
          breaker = ::Ai::WorkflowCircuitBreakerManager.get_or_create_breaker(params[:service_name])
          breaker.close!

          render_success(message: "Circuit breaker closed for #{params[:service_name]}", service_name: params[:service_name], state: breaker.stats)
          log_audit_event("ai.monitoring.circuit_breaker.close", current_user.account, service_name: params[:service_name])
        end

        # POST /api/v1/ai/monitoring/circuit_breakers/reset_all
        def circuit_breakers_reset_all
          ::Ai::WorkflowCircuitBreakerManager.reset_all!
          summary = ::Ai::WorkflowCircuitBreakerManager.health_summary

          render_success(message: "All circuit breakers reset", summary: summary, timestamp: Time.current.iso8601)
          log_audit_event("ai.monitoring.circuit_breakers.reset_all", current_user.account)
        end

        # GET /api/v1/ai/monitoring/circuit_breakers/category/:category
        def circuit_breakers_category
          states = ::Ai::WorkflowCircuitBreakerManager.category_states(params[:category])

          render_success(category: params[:category], circuit_breakers: states, count: states.length, timestamp: Time.current.iso8601)
        end

        # POST /api/v1/ai/monitoring/circuit_breakers/category/:category/reset
        def circuit_breakers_category_reset
          ::Ai::WorkflowCircuitBreakerManager.reset_category!(params[:category])
          states = ::Ai::WorkflowCircuitBreakerManager.category_states(params[:category])

          render_success(message: "Circuit breakers reset for category: #{params[:category]}", category: params[:category], circuit_breakers: states)
          log_audit_event("ai.monitoring.circuit_breakers.category_reset", current_user.account, category: params[:category])
        end

        # GET /api/v1/ai/monitoring/circuit_breakers/monitor
        def circuit_breakers_monitor
          summary = ::Ai::WorkflowCircuitBreakerManager.monitor_and_alert

          render_success(monitored_at: Time.current.iso8601, summary: summary, alerts_triggered: summary[:unhealthy] > 0 || summary[:degraded] > 0)
        end

        # =============================================================================
        # REAL-TIME MONITORING
        # =============================================================================

        # POST /api/v1/ai/monitoring/broadcast
        def broadcast_metrics
          unless params[:account_id].present?
            return render_error("Missing account_id parameter", status: :bad_request)
          end

          account = Account.find(params[:account_id])
          service = Monitoring::UnifiedService.new(account: account)
          metrics = service.get_dashboard(time_range: 1.hour, components: %w[system providers agents workflows])

          ActionCable.server.broadcast(
            "ai_orchestration_#{params[:account_id]}",
            { type: "system_metrics_update", metrics: metrics, timestamp: Time.current.iso8601 }
          )

          render_success(message: "Metrics broadcasted successfully", account_id: params[:account_id], timestamp: Time.current.iso8601)
        rescue ActiveRecord::RecordNotFound
          render_error("Account not found", status: :not_found)
        rescue StandardError => e
          render_internal_error("Failed to broadcast metrics", exception: e)
        end

        # POST /api/v1/ai/monitoring/start
        def start_monitoring
          ::Ai::MonitoringHealthCheckJob.perform_later(current_user.account_id)

          render_success(message: "Real-time monitoring started", account_id: current_user.account_id, timestamp: Time.current.iso8601)
          log_audit_event("ai.monitoring.start", current_user.account)
        rescue StandardError => e
          render_internal_error("Failed to start monitoring", exception: e)
        end

        # POST /api/v1/ai/monitoring/stop
        def stop_monitoring
          render_success(message: "Monitoring stop requested", account_id: current_user.account_id, timestamp: Time.current.iso8601)
          log_audit_event("ai.monitoring.stop", current_user.account)
        end

        private

        def health_service
          @health_service ||= ::Ai::MonitoringHealthService.new(account: current_user.account)
        end

        def current_account
          current_worker&.account || current_user&.account
        end

        def validate_permissions
          return if current_worker

          permission_map = {
            %w[dashboard metrics overview health health_detailed health_connectivity alerts alerts_check
               circuit_breakers_index circuit_breaker_show circuit_breakers_category circuit_breakers_monitor] => "ai.monitoring.read",
            %w[circuit_breaker_reset circuit_breaker_open circuit_breaker_close circuit_breakers_reset_all
               circuit_breakers_category_reset broadcast_metrics start_monitoring stop_monitoring] => "ai.monitoring.manage"
          }

          permission_map.each do |actions, permission|
            return require_permission(permission) if actions.include?(action_name)
          end
        end

        def set_time_range
          range_param = params[:time_range]&.to_i || 3600

          @time_range = case range_param
          when 0..604800 then range_param.seconds
          else 1.hour
          end
        end

        def set_components
          @components = if params[:components].present?
                         params[:components].split(",").map(&:strip) & Monitoring::UnifiedService::COMPONENTS
          else
                         Monitoring::UnifiedService::COMPONENTS
          end
        end
      end
    end
  end
end
