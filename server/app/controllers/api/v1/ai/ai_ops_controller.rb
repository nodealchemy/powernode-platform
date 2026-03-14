# frozen_string_literal: true

# AIOps Controller - Real-Time AI Operations Dashboard
#
# Provides comprehensive observability for AI workflows including latency,
# costs, errors, throughput, and model performance monitoring.
#
# Revenue Model: Monitoring tiers + alerting add-ons
# - Basic monitoring: included in all plans
# - Advanced analytics: $79/mo
# - Custom dashboards + API: $199/mo
# - Business (white-label + embedding): $499/mo
#
module Api
  module V1
    module Ai
      class AiOpsController < ApplicationController
        include AuditLogging

        before_action :validate_permissions
        before_action :set_time_range, only: [ :dashboard, :providers, :workflows, :agents, :cost_analysis ]

        # ==========================================================================
        # DASHBOARD
        # ==========================================================================

        # GET /api/v1/ai/aiops/dashboard
        def dashboard
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          dashboard_data = service.aiops_dashboard(ops_time_range: @time_range)

          render_success({
            dashboard: dashboard_data,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/aiops/health
        def health
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          health_data = service.system_health

          render_success({
            health: health_data,
            timestamp: Time.current.iso8601
          })
        end

        # GET /api/v1/ai/aiops/overview
        def overview
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          time_range = params[:time_range]&.to_i&.seconds || 1.hour

          overview_data = service.system_overview(time_range)

          render_success({
            overview: overview_data,
            timestamp: Time.current.iso8601
          })
        end

        # ==========================================================================
        # PROVIDER METRICS
        # ==========================================================================

        # GET /api/v1/ai/aiops/providers
        def providers
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          provider_data = service.ops_provider_metrics(@time_range)

          render_success({
            providers: provider_data,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/aiops/providers/:id/metrics
        def provider_metrics
          provider = current_user.account.ai_providers.find(params[:id])
          time_range = params[:time_range]&.to_i&.seconds || 1.hour

          metrics = ::Ai::ProviderMetric.for_provider(provider)
                                         .for_account(current_user.account)
                                         .recent(time_range)
                                         .ordered_by_time
                                         .limit(100)

          render_success({
            provider: {
              id: provider.id,
              name: provider.name,
              provider_type: provider.provider_type
            },
            metrics: metrics.map(&:summary),
            time_range: {
              start: time_range.ago.iso8601,
              end: Time.current.iso8601
            }
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        end

        # GET /api/v1/ai/aiops/providers/comparison
        def provider_comparison
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          time_range = params[:time_range]&.to_i&.seconds || 1.hour

          comparison = service.ops_provider_comparison(ops_time_range: time_range)

          render_success({
            comparison: comparison,
            timestamp: Time.current.iso8601
          })
        end

        # ==========================================================================
        # WORKFLOW METRICS
        # ==========================================================================

        # GET /api/v1/ai/aiops/workflows
        def workflows
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          workflow_data = service.ops_workflow_metrics(@time_range)

          render_success({
            workflows: workflow_data,
            time_range: time_range_info
          })
        end

        # ==========================================================================
        # AGENT METRICS
        # ==========================================================================

        # GET /api/v1/ai/aiops/agents
        def agents
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          agent_data = service.ops_agent_metrics(@time_range)

          render_success({
            agents: agent_data,
            time_range: time_range_info
          })
        end

        # ==========================================================================
        # COST ANALYSIS
        # ==========================================================================

        # GET /api/v1/ai/aiops/cost_analysis
        def cost_analysis
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          cost_data = service.ops_cost_analysis(@time_range)

          render_success({
            cost_analysis: cost_data,
            time_range: time_range_info
          })
        end

        # ==========================================================================
        # ALERTS
        # ==========================================================================

        # GET /api/v1/ai/aiops/alerts
        def alerts
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          alerts_data = service.active_alerts

          render_success({
            alerts: alerts_data,
            count: alerts_data.length,
            timestamp: Time.current.iso8601
          })
        end

        # ==========================================================================
        # CIRCUIT BREAKERS
        # ==========================================================================

        # GET /api/v1/ai/aiops/circuit_breakers
        def circuit_breakers
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          cb_status = service.circuit_breaker_status

          render_success({
            circuit_breakers: cb_status,
            timestamp: Time.current.iso8601
          })
        end

        # ==========================================================================
        # REAL-TIME METRICS
        # ==========================================================================

        # GET /api/v1/ai/aiops/real_time
        def real_time
          service = ::Ai::Analytics::DashboardService.new(account: current_user.account)
          real_time_data = service.aiops_real_time_metrics

          render_success(real_time_data)
        end

        # POST /api/v1/ai/aiops/record_metrics
        def record_metrics
          # Allow workers to record metrics
          return render_error("Unauthorized", status: :unauthorized) unless current_worker || current_user

          account = current_worker&.account || current_user.account
          provider = account.ai_providers.find(params[:provider_id])

          service = ::Ai::Analytics::DashboardService.new(account: account)
          service.record_execution_metrics(
            provider: provider,
            execution_data: metrics_params
          )

          render_success({
            message: "Metrics recorded successfully",
            timestamp: Time.current.iso8601
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Provider not found", status: :not_found)
        rescue StandardError => e
          Rails.logger.error "Failed to record metrics: #{e.message}"
          render_error("Failed to record metrics", status: :internal_server_error)
        end

        private

        # ==========================================================================
        # AUTHORIZATION
        # ==========================================================================

        def validate_permissions
          # Skip for workers
          return if current_worker

          case action_name
          when "dashboard", "health", "overview", "providers", "provider_metrics",
               "provider_comparison", "workflows", "agents", "cost_analysis",
               "alerts", "circuit_breakers", "real_time"
            require_permission("ai.aiops.read")
            nil if performed?
          when "record_metrics"
            require_permission("ai.aiops.write")
            nil if performed?
          end
        end

        # ==========================================================================
        # PARAMETER HANDLING
        # ==========================================================================

        def set_time_range
          range_param = params[:time_range]

          @time_range = case range_param
          when "5m" then 5.minutes
          when "15m" then 15.minutes
          when "30m" then 30.minutes
          when "1h" then 1.hour
          when "6h" then 6.hours
          when "24h", "1d" then 24.hours
          when "7d", "1w" then 7.days
          else 1.hour
          end
        end

        def time_range_info
          {
            start: @time_range.ago.iso8601,
            end: Time.current.iso8601,
            period: params[:time_range] || "1h",
            seconds: @time_range.to_i
          }
        end

        def metrics_params
          params.permit(
            :success,
            :timeout,
            :rate_limited,
            :input_tokens,
            :output_tokens,
            :cost_usd,
            :latency_ms,
            :error_type,
            :model_name,
            :circuit_state,
            :consecutive_failures
          ).to_h.symbolize_keys
        end
      end
    end
  end
end
