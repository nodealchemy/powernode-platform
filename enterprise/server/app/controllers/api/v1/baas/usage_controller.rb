# frozen_string_literal: true

module Api
  module V1
    module BaaS
      class UsageController < Api::V1::BaaS::BaseController
        before_action :require_usage_scope

        # POST /api/v1/baas/usage_events
        def create
          service = ::BaaS::UsageMeteringService.new(tenant: current_tenant)
          result = service.record_usage(usage_params)

          if result[:success]
            status = result[:duplicate] ? :ok : :created
            render_success(result[:record], status: status)
          else
            render_error(result[:error])
          end
        end

        # POST /api/v1/baas/usage_events/batch
        def batch
          events = params[:events]
          return render_error("Events array required") unless events.is_a?(Array)
          return render_error("Maximum 1000 events per batch") if events.size > 1000

          service = ::BaaS::UsageMeteringService.new(tenant: current_tenant)
          result = service.record_batch(events.map { |e| e.permit!.to_h })

          status = result[:failed] > 0 ? :multi_status : :created
          render_success(
            {
              successful: result[:successful],
              failed: result[:failed],
              errors: result[:errors]
            },
            status: status
          )
        end

        # GET /api/v1/baas/usage
        def index
          service = ::BaaS::UsageMeteringService.new(tenant: current_tenant)
          result = service.list_records(
            customer_id: params[:customer_id],
            meter_id: params[:meter_id],
            status: params[:status],
            start_date: parse_datetime(params[:start_date]),
            end_date: parse_datetime(params[:end_date]),
            page: params[:page],
            per_page: params[:per_page]
          )

          if result[:success]
            render_success(result[:records], meta: { pagination: result[:pagination] })
          else
            render_error(result[:error])
          end
        end

        # GET /api/v1/baas/usage/summary
        def summary
          return render_error("customer_id required") unless params[:customer_id].present?

          service = ::BaaS::UsageMeteringService.new(tenant: current_tenant)
          result = service.customer_usage_summary(
            customer_id: params[:customer_id],
            start_date: params[:start_date]&.to_date,
            end_date: params[:end_date]&.to_date
          )

          if result[:success]
            render_success(result[:summary])
          else
            render_error(result[:error])
          end
        end

        # GET /api/v1/baas/usage/aggregate
        def aggregate
          return render_error("customer_id required") unless params[:customer_id].present?
          return render_error("meter_id required") unless params[:meter_id].present?

          service = ::BaaS::UsageMeteringService.new(tenant: current_tenant)
          result = service.get_usage(
            customer_id: params[:customer_id],
            meter_id: params[:meter_id],
            start_date: params[:start_date]&.to_date,
            end_date: params[:end_date]&.to_date
          )

          if result[:success]
            render_success(result[:usage])
          else
            render_error(result[:error])
          end
        end

        # GET /api/v1/baas/usage/analytics
        def analytics
          service = ::BaaS::UsageMeteringService.new(tenant: current_tenant)
          result = service.analytics(
            start_date: (params[:start_date]&.to_date || 30.days.ago.to_date),
            end_date: (params[:end_date]&.to_date || Date.current)
          )

          if result[:success]
            render_success(result[:analytics])
          else
            render_error(result[:error])
          end
        end

        private

        def require_usage_scope
          require_scope("usage")
        end

        def parse_datetime(value)
          return nil if value.blank?
          DateTime.iso8601(value)
        rescue ArgumentError, Date::Error
          nil
        end

        def usage_params
          permitted = params.permit(
            :customer_id, :subscription_id, :meter_id, :idempotency_key,
            :quantity, :timestamp, :billing_period_start,
            :billing_period_end, properties: {}, metadata: {}
          )
          # Handle 'action' parameter separately to avoid conflict with Rails controller action
          permitted[:action] = request.request_parameters["action"] if request.request_parameters.key?("action")
          permitted
        end
      end
    end
  end
end
