# frozen_string_literal: true

# ROI Controller - Workflow Revenue Analytics & ROI Tracking
#
# Tracks the business value and ROI of AI workflows with cost attribution
# and revenue impact analysis.
#
# Revenue Model: Premium analytics tiers
# - Basic ROI dashboard: included
# - Advanced analytics: $99/mo
# - Custom KPIs + API: $249/mo
# - Executive reporting: $499/mo
#
module Api
  module V1
    module Ai
      class RoiController < ApplicationController
        include AuditLogging
        include ::Ai::RoiShared

        before_action :validate_permissions
        before_action :set_time_range, only: [ :dashboard, :trends, :by_workflow, :by_agent, :by_provider, :cost_breakdown ]

        # ==========================================================================
        # DASHBOARD
        # ==========================================================================

        # GET /api/v1/ai/roi/dashboard
        def dashboard
          service = ::Ai::Analytics::CostAnalysisService.new(
            account: current_user.account,
            hourly_rate: params[:hourly_rate]&.to_f || 75.0
          )

          dashboard_data = service.roi_dashboard(period: @time_range)

          render_success({
            dashboard: dashboard_data,
            time_range: time_range_info
          })

          log_audit_event("ai.roi.dashboard", current_user.account)
        end

        # GET /api/v1/ai/roi/summary
        def summary
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)
          period = params[:period]&.to_i&.days || 30.days

          summary_data = service.roi_summary_metrics(period)

          render_success({
            summary: summary_data,
            timestamp: Time.current.iso8601
          })
        end

        # ==========================================================================
        # TRENDS
        # ==========================================================================

        # GET /api/v1/ai/roi/trends
        def trends
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)
          trends_data = service.roi_trends(@time_range)

          render_success({
            trends: trends_data,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/roi/daily_metrics
        def daily_metrics
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)
          days = params[:days]&.to_i || 30

          metrics = service.roi_daily_metrics(days: days)

          render_success({
            metrics: metrics,
            days: days
          })
        end

        # ==========================================================================
        # BREAKDOWN ANALYSIS
        # ==========================================================================

        # GET /api/v1/ai/roi/by_workflow
        def by_workflow
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)
          workflow_data = service.roi_by_workflow(@time_range)

          render_success({
            workflows: workflow_data,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/roi/by_agent
        def by_agent
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)
          agent_data = service.roi_by_agent(@time_range)

          render_success({
            agents: agent_data,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/roi/by_provider
        def by_provider
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)
          provider_data = service.roi_cost_by_provider(@time_range)

          render_success({
            providers: provider_data,
            time_range: time_range_info
          })
        end

        # ==========================================================================
        # COST ATTRIBUTION
        # ==========================================================================

        # GET /api/v1/ai/roi/cost_breakdown
        def cost_breakdown
          start_date = @time_range.ago.to_date
          end_date = Date.current

          by_category = ::Ai::CostAttribution.cost_breakdown_by_category(
            current_user.account,
            start_date: start_date,
            end_date: end_date
          )

          by_source = ::Ai::CostAttribution.cost_breakdown_by_source_type(
            current_user.account,
            start_date: start_date,
            end_date: end_date
          )

          by_provider = ::Ai::CostAttribution.cost_breakdown_by_provider(
            current_user.account,
            start_date: start_date,
            end_date: end_date
          )

          daily_trend = ::Ai::CostAttribution.daily_cost_trend(
            current_user.account,
            days: (@time_range / 1.day).to_i
          )

          top_sources = ::Ai::CostAttribution.top_cost_sources(
            current_user.account,
            limit: 10,
            start_date: start_date,
            end_date: end_date
          )

          render_success({
            cost_breakdown: {
              by_category: by_category,
              by_source_type: by_source,
              by_provider: by_provider,
              daily_trend: daily_trend,
              top_sources: top_sources
            },
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/roi/attributions
        def attributions
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 50, 200 ].min

          attributions = ::Ai::CostAttribution.for_account(current_user.account)
                                               .order(attribution_date: :desc, created_at: :desc)

          # Apply filters
          if params[:date].present?
            attributions = attributions.for_date(Date.parse(params[:date]))
          elsif params[:start_date].present? && params[:end_date].present?
            attributions = attributions.for_date_range(
              Date.parse(params[:start_date]),
              Date.parse(params[:end_date])
            )
          end

          attributions = attributions.by_category(params[:category]) if params[:category].present?
          attributions = attributions.by_source_type(params[:source_type]) if params[:source_type].present?
          attributions = attributions.for_provider(params[:provider_id]) if params[:provider_id].present?

          paginated = attributions.page(page).per(per_page)

          render_success({
            attributions: paginated.map(&:summary),
            pagination: pagination_data(paginated)
          })
        end
      end
    end
  end
end
