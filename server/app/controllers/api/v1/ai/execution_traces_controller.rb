# frozen_string_literal: true

module Api
  module V1
    module Ai
      # ExecutionTracesController - API endpoints for execution tracing
      #
      # Provides access to LangSmith-style execution traces for debugging
      # and monitoring AI operations.
      class ExecutionTracesController < ApplicationController
        before_action :authenticate_user!
        before_action :set_trace, only: [ :show, :spans, :timeline ]

        # GET /api/v1/ai/execution_traces
        # List recent execution traces
        def index
          authorize_action!("ai_monitoring.read")

          traces = Ai::TracingService.list_traces(
            account: current_account,
            limit: params[:limit]&.to_i || 50,
            type: params[:type],
            status: params[:status]
          )

          render_success(data: traces)
        end

        # GET /api/v1/ai/execution_traces/:id
        # Get a single trace with all spans
        def show
          authorize_action!("ai_monitoring.read")

          trace_data = Ai::TracingService.get_trace(@trace.trace_id, account: current_account)

          if trace_data
            render_success(data: trace_data)
          else
            render_error(
              message: "Trace not found",
              status: :not_found
            )
          end
        end

        # GET /api/v1/ai/execution_traces/:id/spans
        # Get spans for a trace
        def spans
          authorize_action!("ai_monitoring.read")

          spans = @trace.execution_trace_spans.order(:started_at).map(&:as_json)

          render_success(data: {
            trace_id: @trace.trace_id,
            spans: spans,
            summary: {
              total: spans.size,
              by_type: spans.group_by { |s| s[:type] }.transform_values(&:count),
              by_status: spans.group_by { |s| s[:status] }.transform_values(&:count)
            }
          })
        end

        # GET /api/v1/ai/execution_traces/:id/timeline
        # Get timeline visualization data
        def timeline
          authorize_action!("ai_monitoring.read")

          render_success(data: {
            trace_id: @trace.trace_id,
            name: @trace.name,
            type: @trace.trace_type,
            status: @trace.status,
            started_at: @trace.started_at&.iso8601,
            completed_at: @trace.completed_at&.iso8601,
            duration_ms: @trace.duration_ms,
            timeline: @trace.timeline,
            summary: {
              total_tokens: @trace.total_tokens,
              total_cost: @trace.total_cost,
              success_rate: @trace.success_rate
            }
          })
        end

        # GET /api/v1/ai/execution_traces/summary
        # Get summary statistics for traces
        def summary
          authorize_action!("ai_monitoring.read")

          time_range = params[:time_range] || "24h"
          start_time = parse_time_range(time_range)

          traces = Ai::ExecutionTrace.where(account: current_account)
                                     .where("started_at >= ?", start_time)

          summary_data = {
            total_traces: traces.count,
            by_status: traces.group(:status).count,
            by_type: traces.group(:trace_type).count,
            total_tokens: traces.sum(:total_tokens),
            total_cost: traces.sum(:total_cost).round(6),
            avg_duration_ms: traces.average(:duration_ms)&.round,
            error_rate: calculate_error_rate(traces),
            time_range: time_range,
            start_time: start_time.iso8601
          }

          render_success(data: summary_data)
        end

        private

        def set_trace
          @trace = Ai::ExecutionTrace.find_by!(
            id: params[:id],
            account_id: current_account.id
          )
        rescue ActiveRecord::RecordNotFound
          # Try finding by trace_id
          @trace = Ai::ExecutionTrace.find_by!(
            trace_id: params[:id],
            account_id: current_account.id
          )
        end

        def parse_time_range(range)
          case range
          when "1h"
            1.hour.ago
          when "6h"
            6.hours.ago
          when "24h"
            24.hours.ago
          when "7d"
            7.days.ago
          when "30d"
            30.days.ago
          else
            24.hours.ago
          end
        end

        def calculate_error_rate(traces)
          return 0.0 if traces.empty?

          failed = traces.where(status: "failed").count
          (failed.to_f / traces.count * 100).round(2)
        end

        def authorize_action!(permission)
          unless current_user.has_permission?(permission)
            render_error(
              message: "You don't have permission to access execution traces",
              status: :forbidden
            )
          end
        end
      end
    end
  end
end
