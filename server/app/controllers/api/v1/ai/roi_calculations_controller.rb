# frozen_string_literal: true

# ROI Calculations Controller - ROI Metrics, Projections & Comparisons
#
# Handles ROI metric queries, projections, recommendations, period comparison,
# and metric calculation/aggregation endpoints.
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
      class RoiCalculationsController < ApplicationController
        include AuditLogging
        include ::Ai::RoiShared

        before_action :validate_permissions

        # ==========================================================================
        # ROI METRICS
        # ==========================================================================

        # GET /api/v1/ai/roi/calculations/metrics
        def metrics
          page = params[:page]&.to_i || 1
          per_page = [ params[:per_page]&.to_i || 30, 100 ].min

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

        # GET /api/v1/ai/roi/calculations/metrics/:id
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

        # GET /api/v1/ai/roi/calculations/projections
        def projections
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)
          period = params[:period]&.to_i&.days || 30.days

          projection_data = service.roi_projections(period)

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

        # GET /api/v1/ai/roi/calculations/recommendations
        def recommendations
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)
          period = params[:period]&.to_i&.days || 30.days

          recommendations_data = service.roi_recommendations(period)

          render_success({
            recommendations: recommendations_data,
            generated_at: Time.current.iso8601
          })
        end

        # ==========================================================================
        # PERIOD COMPARISON
        # ==========================================================================

        # GET /api/v1/ai/roi/calculations/compare
        def compare
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)

          current_period = params[:current_period]&.to_i&.days || 30.days
          previous_period = params[:previous_period]&.to_i&.days || 30.days

          comparison = service.roi_compare_periods(
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

        # POST /api/v1/ai/roi/calculations/calculate
        def calculate
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)

          if params[:date].present?
            date = Date.parse(params[:date])
            metric = service.roi_calculate_for_date(date: date)

            render_success({
              metric: metric.summary,
              message: "ROI metrics calculated for #{date}"
            })
          elsif params[:start_date].present? && params[:end_date].present?
            start_date = Date.parse(params[:start_date])
            end_date = Date.parse(params[:end_date])

            metrics = service.roi_calculate_for_range(start_date: start_date, end_date: end_date)

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
            metric = service.roi_calculate_for_date(date: Date.current)

            render_success({
              metric: metric.summary,
              message: "ROI metrics calculated for today"
            })
          end

          log_audit_event("ai.roi.calculate", current_user.account)
        rescue StandardError => e
          render_internal_error("Calculation failed", exception: e)
        end

        # POST /api/v1/ai/roi/calculations/aggregate
        def aggregate
          service = ::Ai::Analytics::CostAnalysisService.new(account: current_user.account)

          period_type = params[:period_type] || "weekly"
          period_date = params[:period_date].present? ? Date.parse(params[:period_date]) : Date.current

          result = service.roi_aggregate_metrics(period_type: period_type, period_date: period_date)

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
          render_internal_error("Aggregation failed", exception: e)
        end
      end
    end
  end
end
