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

        before_action :validate_permissions
        before_action :set_time_range, only: [:dashboard, :trends, :by_workflow, :by_agent, :by_provider, :cost_breakdown]

        # ==========================================================================
        # DASHBOARD
        # ==========================================================================

        # GET /api/v1/ai/roi/dashboard
        def dashboard
          service = ::Ai::RoiAnalyticsService.new(
            account: current_user.account,
            hourly_rate: params[:hourly_rate]&.to_f || 75.0
          )

          dashboard_data = service.dashboard(period: @time_range)

          render_success({
            dashboard: dashboard_data,
            time_range: time_range_info
          })

          log_audit_event("ai.roi.dashboard", current_user.account)
        end

        # GET /api/v1/ai/roi/summary
        def summary
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)
          period = params[:period]&.to_i&.days || 30.days

          summary_data = service.summary_metrics(period)

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
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)
          trends_data = service.roi_trends(@time_range)

          render_success({
            trends: trends_data,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/roi/daily_metrics
        def daily_metrics
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)
          days = params[:days]&.to_i || 30

          metrics = service.daily_metrics(days: days)

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
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)
          workflow_data = service.roi_by_workflow(@time_range)

          render_success({
            workflows: workflow_data,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/roi/by_agent
        def by_agent
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)
          agent_data = service.roi_by_agent(@time_range)

          render_success({
            agents: agent_data,
            time_range: time_range_info
          })
        end

        # GET /api/v1/ai/roi/by_provider
        def by_provider
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)
          provider_data = service.cost_by_provider(@time_range)

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
          per_page = [params[:per_page]&.to_i || 50, 200].min

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

        # ==========================================================================
        # ROI METRICS
        # ==========================================================================

        # GET /api/v1/ai/roi/metrics
        def metrics
          page = params[:page]&.to_i || 1
          per_page = [params[:per_page]&.to_i || 30, 100].min

          metrics = ::Ai::RoiMetric.for_account(current_user.account)
                                    .order(period_date: :desc)

          # Apply filters
          metrics = metrics.for_type(params[:metric_type]) if params[:metric_type].present?
          metrics = metrics.for_period_type(params[:period_type]) if params[:period_type].present?

          if params[:start_date].present? && params[:end_date].present?
            metrics = metrics.for_date_range(
              Date.parse(params[:start_date]),
              Date.parse(params[:end_date])
            )
          end

          paginated = metrics.page(page).per(per_page)

          render_success({
            metrics: paginated.map(&:summary),
            pagination: pagination_data(paginated)
          })
        end

        # GET /api/v1/ai/roi/metrics/:id
        def show_metric
          metric = ::Ai::RoiMetric.find(params[:id])

          unless metric.account_id == current_user.account_id
            return render_error("Metric not found", status: :not_found)
          end

          render_success({
            metric: metric.summary
          })
        rescue ActiveRecord::RecordNotFound
          render_error("Metric not found", status: :not_found)
        end

        # ==========================================================================
        # PROJECTIONS
        # ==========================================================================

        # GET /api/v1/ai/roi/projections
        def projections
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)
          period = params[:period]&.to_i&.days || 30.days

          projection_data = service.projections(period)

          if projection_data
            render_success({
              projections: projection_data,
              timestamp: Time.current.iso8601
            })
          else
            render_success({
              projections: nil,
              message: "Insufficient data for projections. Need at least 7 days of metrics."
            })
          end
        end

        # ==========================================================================
        # RECOMMENDATIONS
        # ==========================================================================

        # GET /api/v1/ai/roi/recommendations
        def recommendations
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)
          period = params[:period]&.to_i&.days || 30.days

          recommendations_data = service.recommendations(period)

          render_success({
            recommendations: recommendations_data,
            generated_at: Time.current.iso8601
          })
        end

        # ==========================================================================
        # PERIOD COMPARISON
        # ==========================================================================

        # GET /api/v1/ai/roi/compare
        def compare
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)

          current_period = params[:current_period]&.to_i&.days || 30.days
          previous_period = params[:previous_period]&.to_i&.days || 30.days

          comparison = service.compare_periods(
            current_period: current_period,
            previous_period: previous_period
          )

          render_success({
            comparison: comparison,
            generated_at: Time.current.iso8601
          })
        end

        # ==========================================================================
        # METRIC CALCULATION
        # ==========================================================================

        # POST /api/v1/ai/roi/calculate
        def calculate
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)

          if params[:date].present?
            date = Date.parse(params[:date])
            metric = service.calculate_for_date(date: date)

            render_success({
              metric: metric.summary,
              message: "ROI metrics calculated for #{date}"
            })
          elsif params[:start_date].present? && params[:end_date].present?
            start_date = Date.parse(params[:start_date])
            end_date = Date.parse(params[:end_date])

            metrics = service.calculate_for_range(start_date: start_date, end_date: end_date)

            render_success({
              metrics_calculated: metrics.count,
              date_range: {
                start: start_date,
                end: end_date
              },
              message: "ROI metrics calculated for date range"
            })
          else
            # Default to today
            metric = service.calculate_for_date(date: Date.current)

            render_success({
              metric: metric.summary,
              message: "ROI metrics calculated for today"
            })
          end

          log_audit_event("ai.roi.calculate", current_user.account)
        rescue StandardError => e
          Rails.logger.error "ROI calculation failed: #{e.message}"
          render_error("Calculation failed: #{e.message}", status: :internal_server_error)
        end

        # POST /api/v1/ai/roi/aggregate
        def aggregate
          service = ::Ai::RoiAnalyticsService.new(account: current_user.account)

          period_type = params[:period_type] || "weekly"
          period_date = params[:period_date].present? ? Date.parse(params[:period_date]) : Date.current

          result = service.aggregate_metrics(period_type: period_type, period_date: period_date)

          if result
            render_success({
              aggregation: result,
              message: "ROI metrics aggregated for #{period_type} period"
            })
          else
            render_success({
              aggregation: nil,
              message: "No daily metrics found for aggregation"
            })
          end

          log_audit_event("ai.roi.aggregate", current_user.account,
            metadata: { period_type: period_type, period_date: period_date }
          )
        rescue StandardError => e
          Rails.logger.error "ROI aggregation failed: #{e.message}"
          render_error("Aggregation failed: #{e.message}", status: :internal_server_error)
        end

        private

        # ==========================================================================
        # AUTHORIZATION
        # ==========================================================================

        def validate_permissions
          case action_name
          when "dashboard", "summary", "trends", "daily_metrics", "by_workflow",
               "by_agent", "by_provider", "cost_breakdown", "attributions",
               "metrics", "show_metric", "projections", "recommendations", "compare"
            require_permission("ai.roi.read")
          when "calculate", "aggregate"
            require_permission("ai.roi.manage")
          end
        end

        # ==========================================================================
        # PARAMETER HANDLING
        # ==========================================================================

        def set_time_range
          range_param = params[:time_range]

          @time_range = case range_param
          when "7d", "1w" then 7.days
          when "14d", "2w" then 14.days
          when "30d", "1m" then 30.days
          when "60d", "2m" then 60.days
          when "90d", "3m" then 90.days
          when "180d", "6m" then 180.days
          when "365d", "1y" then 365.days
          else 30.days
          end
        end

        def time_range_info
          {
            start: @time_range.ago.to_date.iso8601,
            end: Date.current.iso8601,
            period: params[:time_range] || "30d",
            days: (@time_range / 1.day).to_i
          }
        end

        def pagination_data(collection)
          {
            current_page: collection.current_page,
            per_page: collection.limit_value,
            total_pages: collection.total_pages,
            total_count: collection.total_count
          }
        end
      end
    end
  end
end
