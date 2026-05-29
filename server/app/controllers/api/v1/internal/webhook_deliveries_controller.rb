# frozen_string_literal: true

# Internal API for webhook delivery operations (worker callback).
# Backs the worker's Webhooks::WebhookDeliveryJob / WebhookRetryJob, which GET
# the delivery details, PATCH the outcome, and PATCH increment_attempt on retry.
class Api::V1::Internal::WebhookDeliveriesController < Api::V1::Internal::InternalBaseController
  # GET /api/v1/internal/webhook_deliveries/:id
  def show
    delivery = ::WebhookDelivery.find(params[:id])
    endpoint = delivery.webhook_endpoint

    render_success({
      id: delivery.id,
      webhook_url: endpoint.url,
      payload: delivery.webhook_event&.payload,
      headers: endpoint.headers || {},
      custom_headers: endpoint.custom_headers || {},
      attempt: delivery.attempt_number,
      endpoint_id: delivery.webhook_endpoint_id,
      circuit_broken: endpoint.circuit_broken?,
      circuit_cooldown_until: endpoint.circuit_cooldown_until,
      payload_detail_level: endpoint.payload_detail_level,
      status: delivery.status
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Webhook delivery not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch webhook delivery: #{e.message}"
    render_error("Failed to fetch delivery", status: :internal_server_error)
  end

  # PATCH /api/v1/internal/webhook_deliveries/:id
  # Records the delivery outcome. Retry scheduling/attempt counting is driven by
  # the worker (WebhookRetryJob + increment_attempt), so this only persists state.
  def update
    delivery = ::WebhookDelivery.find(params[:id])
    meta = params[:metadata] || {}

    case params[:status]
    when "delivered"
      delivery.update!(
        status: "success",
        response_status: meta[:status_code],
        response_body: meta[:response_body],
        attempted_at: Time.current
      )
    when "failed"
      delivery.update!(
        status: "failed",
        response_status: meta[:status_code],
        response_body: meta[:response_body],
        error_message: meta[:error_message],
        attempted_at: Time.current
      )
    when "skipped"
      delivery.update!(
        status: "failed",
        error_message: meta[:error_message] || "Skipped (circuit breaker open)",
        attempted_at: Time.current
      )
    else # "in_progress" or any other transient marker — record the attempt time only
      delivery.update!(attempted_at: Time.current)
    end

    Rails.logger.info "Webhook delivery status updated: #{delivery.id} -> #{params[:status]}"

    render_success({
      id: delivery.id,
      status: delivery.status,
      message: "Delivery status updated"
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Webhook delivery not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to update webhook delivery: #{e.message}"
    render_error("Failed to update delivery", status: :internal_server_error)
  end

  # PATCH /api/v1/internal/webhook_deliveries/:id/increment_attempt
  def increment_attempt
    delivery = ::WebhookDelivery.find(params[:id])

    delivery.increment!(:attempt_number)

    Rails.logger.info "Webhook delivery attempt incremented: #{delivery.id} (attempt #{delivery.attempt_number})"

    render_success({
      id: delivery.id,
      attempt: delivery.attempt_number,
      message: "Attempt incremented"
    })
  rescue ActiveRecord::RecordNotFound
    render_error("Webhook delivery not found", status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to increment attempt: #{e.message}"
    render_error("Failed to increment attempt", status: :internal_server_error)
  end
end
