# frozen_string_literal: true

module Api
  module V1
    module Internal
      class WebhookEndpointsController < InternalBaseController
        before_action :set_endpoint

        # GET /api/v1/internal/webhook_endpoints/:id
        def show
          render_success({
            endpoint: {
              id: @endpoint.id,
              url: @endpoint.url,
              status: @endpoint.status,
              is_active: @endpoint.is_active,
              can_deliver: @endpoint.can_deliver?,
              circuit_broken: @endpoint.circuit_broken?,
              circuit_status: @endpoint.circuit_status,
              circuit_cooldown_until: @endpoint.circuit_cooldown_until&.iso8601,
              consecutive_failures: @endpoint.consecutive_failures,
              circuit_break_threshold: @endpoint.circuit_break_threshold,
              payload_detail_level: @endpoint.payload_detail_level,
              custom_headers: @endpoint.custom_headers
            }
          })
        end

        # POST /api/v1/internal/webhook_endpoints/:id/record_success
        def record_success
          @endpoint.record_success!
          render_success({
            message: "Success recorded",
            circuit_status: @endpoint.circuit_status,
            consecutive_failures: @endpoint.consecutive_failures
          })
        end

        # POST /api/v1/internal/webhook_endpoints/:id/record_failure
        def record_failure
          @endpoint.record_failure!

          response_data = {
            message: "Failure recorded",
            circuit_status: @endpoint.circuit_status,
            consecutive_failures: @endpoint.consecutive_failures
          }

          if @endpoint.circuit_broken?
            response_data[:circuit_broken] = true
            response_data[:circuit_cooldown_until] = @endpoint.circuit_cooldown_until&.iso8601
          end

          render_success(response_data)
        end

        private

        def set_endpoint
          @endpoint = WebhookEndpoint.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Webhook endpoint not found", status: :not_found)
        end
      end
    end
  end
end
