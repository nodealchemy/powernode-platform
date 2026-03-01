# frozen_string_literal: true

module Api
  module V1
    class UsageController < ApplicationController
      before_action -> { require_permission("billing.read") }, only: [ :dashboard, :meter, :history, :export ]
      before_action -> { require_permission("billing.manage") }, only: [ :set_quota, :reset_quotas ]

      # GET /api/v1/usage/dashboard
      def dashboard
        service = UsageTrackingService.new(account: current_account)
        data = service.dashboard_data

        render_success(data: data)
      end

      # POST /api/v1/usage_events
      def track_event
        service = UsageTrackingService.new(account: current_account)
        result = service.track_event(event_params)

        if result[:success]
          render_success(
            data: result[:event].summary,
            message: result[:duplicate] ? "Event already recorded (idempotent)" : "Event tracked successfully",
            status: result[:duplicate] ? :ok : :created
          )
        else
          render_error(result[:error], status: :unprocessable_content)
        end
      end

      # POST /api/v1/usage_events/batch
      def track_events_batch
        events = params[:events]

        unless events.is_a?(Array) && events.present?
          return render_error("Events array is required", status: :bad_request)
        end

        if events.size > 1000
          return render_error("Maximum 1000 events per batch", status: :bad_request)
        end

        service = UsageTrackingService.new(account: current_account)
        result = service.track_events_batch(events.map { |e| event_params_from(e) })

        render_success(
          data: {
            success_count: result[:success],
            failed_count: result[:failed],
            errors: result[:errors]
          },
          message: "Batch processing complete"
        )
      end

      # GET /api/v1/usage/meters/:slug
      def meter
        service = UsageTrackingService.new(account: current_account)
        result = service.meter_usage(
          params[:slug],
          period_start: params[:period_start]&.to_date,
          period_end: params[:period_end]&.to_date
        )

        if result[:success]
          render_success(data: result.except(:success))
        else
          render_error(result[:error], status: :not_found)
        end
      end

      # GET /api/v1/usage/meters
      def meters
        meters = UsageMeter.active.order(:name)

        render_success(
          data: meters.map(&:summary)
        )
      end

      # GET /api/v1/usage/history
      def history
        service = UsageTrackingService.new(account: current_account)
        result = service.usage_history(
          meter_slug: params[:meter_slug],
          days: (params[:days] || 30).to_i
        )

        render_success(data: result)
      end

      # GET /api/v1/usage/billing_summary
      def billing_summary
        period_start = params[:period_start]&.to_date || Date.current.beginning_of_month
        period_end = params[:period_end]&.to_date || Date.current.end_of_month

        service = UsageTrackingService.new(account: current_account)
        result = service.get_billing_summary(
          period_start: period_start,
          period_end: period_end
        )

        render_success(data: result)
      end

      # GET /api/v1/usage/quotas
      def quotas
        quotas = current_account.usage_quotas.includes(:usage_meter)

        render_success(
          data: quotas.map(&:summary)
        )
      end

      # POST /api/v1/usage/quotas
      def set_quota
        service = UsageTrackingService.new(account: current_account)
        result = service.set_quota(
          meter_slug: params[:meter_slug],
          soft_limit: params[:soft_limit],
          hard_limit: params[:hard_limit],
          allow_overage: params[:allow_overage] != false,
          overage_rate: params[:overage_rate]
        )

        if result[:success]
          render_success(
            data: result[:quota],
            message: "Quota set successfully"
          )
        else
          render_error(result[:error] || result[:errors]&.join(", "), status: :unprocessable_content)
        end
      end

      # POST /api/v1/usage/quotas/reset
      def reset_quotas
        service = UsageTrackingService.new(account: current_account)
        result = service.reset_quotas

        if result[:success]
          render_success(message: "Quotas reset successfully")
        else
          render_error("Failed to reset quotas", status: :internal_server_error)
        end
      end

      # GET /api/v1/usage/export
      def export
        start_date = params[:start_date]&.to_date || 30.days.ago.to_date
        end_date = params[:end_date]&.to_date || Date.current

        service = UsageTrackingService.new(account: current_account)
        format = params[:format] == "csv" ? :csv : :json

        result = service.export_usage(
          start_date: start_date,
          end_date: end_date,
          format: format
        )

        if format == :csv
          send_data result,
                    filename: "usage_export_#{start_date}_#{end_date}.csv",
                    type: "text/csv"
        else
          render_success(data: result)
        end
      end

      private

      def event_params
        params.permit(
          :event_id, :meter_slug, :quantity, :timestamp, :source, :user_id,
          properties: {}, metadata: {}
        ).to_h.symbolize_keys
      end

      def event_params_from(event_hash)
        event_hash.slice(
          :event_id, :meter_slug, :quantity, :timestamp, :source, :user_id,
          :properties, :metadata
        ).symbolize_keys
      end
    end
  end
end
