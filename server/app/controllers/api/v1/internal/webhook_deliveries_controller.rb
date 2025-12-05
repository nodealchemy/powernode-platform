# frozen_string_literal: true

# Internal API for webhook delivery operations
class Api::V1::Internal::WebhookDeliveriesController < ApplicationController
  skip_before_action :authenticate_request
  before_action :authenticate_service_token

  # GET /api/v1/internal/webhook_deliveries/:id
  def show
    delivery = AppWebhookDelivery.find(params[:id])

    render_success({
      id: delivery.id,
      webhook_url: delivery.app_webhook.url,
      payload: delivery.payload,
      headers: delivery.app_webhook.headers || {},
      attempt: delivery.attempts,
      status: delivery.status
    })
  rescue ActiveRecord::RecordNotFound
    render_error('Webhook delivery not found', status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to fetch webhook delivery: #{e.message}"
    render_error('Failed to fetch delivery', status: :internal_server_error)
  end

  # PATCH /api/v1/internal/webhook_deliveries/:id
  def update
    delivery = AppWebhookDelivery.find(params[:id])

    update_params = {
      status: params[:status]
    }

    if params[:metadata]
      update_params[:response_code] = params[:metadata][:status_code]
      update_params[:response_body] = params[:metadata][:response_body]
      update_params[:response_time_ms] = params[:metadata][:response_time_ms]
      update_params[:error_message] = params[:metadata][:error_message]
    end

    case params[:status]
    when 'in_progress'
      update_params[:started_at] = Time.current
    when 'delivered'
      update_params[:delivered_at] = Time.current
    when 'failed'
      update_params[:failed_at] = Time.current
    end

    delivery.update!(update_params)

    Rails.logger.info "Webhook delivery status updated: #{delivery.id} -> #{params[:status]}"

    render_success({
      id: delivery.id,
      status: delivery.status,
      message: 'Delivery status updated'
    })
  rescue ActiveRecord::RecordNotFound
    render_error('Webhook delivery not found', status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to update webhook delivery: #{e.message}"
    render_error('Failed to update delivery', status: :internal_server_error)
  end

  # PATCH /api/v1/internal/webhook_deliveries/:id/increment_attempt
  def increment_attempt
    delivery = AppWebhookDelivery.find(params[:id])

    delivery.increment!(:attempts)

    Rails.logger.info "Webhook delivery attempt incremented: #{delivery.id} (attempt #{delivery.attempts})"

    render_success({
      id: delivery.id,
      attempts: delivery.attempts,
      message: 'Attempt incremented'
    })
  rescue ActiveRecord::RecordNotFound
    render_error('Webhook delivery not found', status: :not_found)
  rescue StandardError => e
    Rails.logger.error "Failed to increment attempt: #{e.message}"
    render_error('Failed to increment attempt', status: :internal_server_error)
  end

  private

  def authenticate_service_token
    token = request.headers['Authorization']&.split(' ')&.last

    unless token.present?
      render_error('Service token required', status: :unauthorized)
      return
    end

    begin
      payload = JWT.decode(token, Rails.application.config.jwt_secret_key, true, algorithm: 'HS256').first

      unless payload['service'] == 'worker' && payload['type'] == 'service'
        render_error('Invalid service token', status: :unauthorized)
        return
      end

    rescue JWT::DecodeError, JWT::ExpiredSignature
      render_error('Invalid service token', status: :unauthorized)
    end
  end
end
