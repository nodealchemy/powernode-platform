# frozen_string_literal: true

class Api::V1::AppWebhooksController < ApplicationController
  include AuditLogging

  before_action :set_app
  before_action :set_app_webhook, only: [ :show, :update, :destroy, :activate, :deactivate, :test, :regenerate_secret ]

  # GET /api/v1/apps/:app_id/webhooks
  def index
    authorize_permission!("apps.read")

    webhooks = @app.app_webhooks.includes(:app_webhook_deliveries)
    webhooks = webhooks.where("name ILIKE ?", "%#{params[:search]}%") if params[:search].present?
    webhooks = webhooks.where(event_type: params[:event_type]) if params[:event_type].present?
    webhooks = webhooks.where(is_active: params[:active]) if params[:active].present?

    page = (params[:page] || 1).to_i
    per_page = [ (params[:per_page] || 20).to_i, 100 ].min
    offset = (page - 1) * per_page

    total_count = webhooks.count
    webhooks = webhooks.order(:name).limit(per_page).offset(offset)

    render_success(
      data: webhooks.map { |webhook| webhook_data(webhook) },
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count / per_page.to_f).ceil
      }
    )
  end

  # GET /api/v1/apps/:app_id/webhooks/:id
  def show
    authorize_permission!("apps.read")

    render_success(
      data: webhook_data(@app_webhook, include_analytics: true)
    )
  end

  # POST /api/v1/apps/:app_id/webhooks
  def create
    authorize_permission!("apps.update")

    @app_webhook = @app.app_webhooks.build(webhook_params)

    if @app_webhook.save
      render_success(
        message: "Webhook created successfully",
        data: webhook_data(@app_webhook),
        status: :created
      )
    else
      render_validation_error(@app_webhook)
    end
  end

  # PUT /api/v1/apps/:app_id/webhooks/:id
  def update
    authorize_permission!("apps.update")

    if @app_webhook.update(webhook_params)
      render_success(
        message: "Webhook updated successfully",
        data: webhook_data(@app_webhook)
      )
    else
      render_validation_error(@app_webhook)
    end
  end

  # DELETE /api/v1/apps/:app_id/webhooks/:id
  def destroy
    authorize_permission!("apps.delete")

    @app_webhook.destroy!

    render_success(
      message: "Webhook deleted successfully"
    )
  end

  # POST /api/v1/apps/:app_id/webhooks/:id/activate
  def activate
    authorize_permission!("apps.update")

    @app_webhook.update!(is_active: true)

    render_success(
      message: "Webhook activated successfully",
      data: webhook_data(@app_webhook)
    )
  end

  # POST /api/v1/apps/:app_id/webhooks/:id/deactivate
  def deactivate
    authorize_permission!("apps.update")

    @app_webhook.update!(is_active: false)

    render_success(
      message: "Webhook deactivated successfully",
      data: webhook_data(@app_webhook)
    )
  end

  # POST /api/v1/apps/:app_id/webhooks/:id/test
  def test
    authorize_permission!("apps.update")

    test_event_data = params[:test_data] || { test: true, timestamp: Time.current.iso8601 }
    event_id = SecureRandom.uuid

    begin
      delivery = @app_webhook.deliver(test_event_data, event_id)

      render_success(
        message: "Test webhook delivery initiated",
        data: {
          delivery_id: delivery.delivery_id,
          event_id: delivery.event_id,
          status: delivery.status,
          payload: @app_webhook.build_payload(test_event_data)
        }
      )
    rescue => e
      render_error(
        "Failed to test webhook",
        :unprocessable_content,
        details: [ e.message ]
      )
    end
  end

  # POST /api/v1/apps/:app_id/webhooks/:id/regenerate_secret
  def regenerate_secret
    authorize_permission!("apps.update")

    old_secret = @app_webhook.secret_token[0..10] + "..."
    @app_webhook.update!(secret_token: SecureRandom.hex(32))
    new_secret = @app_webhook.secret_token[0..10] + "..."

    render_success(
      message: "Webhook secret token regenerated successfully",
      data: {
        secret_token: @app_webhook.secret_token,
        old_secret_preview: old_secret,
        new_secret_preview: new_secret
      }
    )
  end

  # GET /api/v1/apps/:app_id/webhooks/:id/deliveries
  def deliveries
    authorize_permission!("apps.read")

    days = [ (params[:days] || 7).to_i, 30 ].min
    deliveries = @app_webhook.app_webhook_deliveries
                            .where("created_at > ?", days.days.ago)
                            .order(created_at: :desc)

    deliveries = deliveries.where(status: params[:status]) if params[:status].present?
    deliveries = deliveries.where(event_id: params[:event_id]) if params[:event_id].present?

    page = (params[:page] || 1).to_i
    per_page = [ (params[:per_page] || 50).to_i, 100 ].min
    offset = (page - 1) * per_page

    total_count = deliveries.count
    deliveries = deliveries.limit(per_page).offset(offset)

    render_success(
      data: deliveries.map { |delivery| delivery_data(delivery) },
      pagination: {
        current_page: page,
        per_page: per_page,
        total_count: total_count,
        total_pages: (total_count / per_page.to_f).ceil
      }
    )
  end

  # GET /api/v1/apps/:app_id/webhooks/:id/analytics
  def analytics
    authorize_permission!("apps.read")

    days = [ (params[:days] || 30).to_i, 90 ].min
    deliveries = @app_webhook.app_webhook_deliveries.where("created_at > ?", days.days.ago)

    analytics_data = {
      total_deliveries: deliveries.count,
      deliveries_by_day: deliveries.group_by_day(:created_at, last: days).count,
      deliveries_by_status: deliveries.group(:status).count,
      success_rate: @app_webhook.success_rate,
      failure_rate: @app_webhook.failure_rate,
      average_response_time: @app_webhook.average_response_time,
      pending_deliveries: @app_webhook.pending_deliveries_count,
      failed_deliveries: @app_webhook.failed_deliveries_count,
      retry_stats: deliveries.retry_stats
    }

    render_success(
      data: analytics_data
    )
  end

  private

  def set_app
    @app = current_account.apps.find(params[:app_id])
  rescue ActiveRecord::RecordNotFound
    render_error("App not found", status: :not_found)
  end

  def set_app_webhook
    @app_webhook = @app.app_webhooks.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_error("Webhook not found", status: :not_found)
  end

  def webhook_params
    params.require(:app_webhook).permit(
      :name, :slug, :description, :event_type, :url, :http_method, :is_active,
      :timeout_seconds, :max_retries, :content_type,
      headers: {}, payload_template: {}, authentication: {}, retry_config: {}, metadata: {}
    )
  end

  def webhook_data(webhook, include_analytics: false)
    data = {
      id: webhook.id,
      name: webhook.name,
      slug: webhook.slug,
      description: webhook.description,
      event_type: webhook.event_type,
      url: webhook.url,
      http_method: webhook.http_method,
      headers: webhook.headers_json,
      payload_template: webhook.payload_template_json,
      authentication: webhook.authentication_json,
      retry_config: webhook.retry_config_json,
      is_active: webhook.is_active,
      secret_token: webhook.secret_token,
      timeout_seconds: webhook.timeout_seconds,
      max_retries: webhook.max_retries,
      content_type: webhook.content_type,
      metadata: webhook.metadata,
      created_at: webhook.created_at,
      updated_at: webhook.updated_at
    }

    if include_analytics
      data[:analytics] = {
        total_deliveries: webhook.total_deliveries,
        deliveries_last_24h: webhook.deliveries_last_24h,
        success_rate: webhook.success_rate,
        failure_rate: webhook.failure_rate,
        average_response_time: webhook.average_response_time,
        pending_deliveries: webhook.pending_deliveries_count,
        failed_deliveries: webhook.failed_deliveries_count
      }
    end

    data
  end

  def delivery_data(delivery)
    {
      id: delivery.id,
      delivery_id: delivery.delivery_id,
      event_id: delivery.event_id,
      status: delivery.status,
      status_code: delivery.status_code,
      response_time_ms: delivery.response_time_ms,
      attempt_number: delivery.attempt_number,
      error_message: delivery.error_message,
      delivered_at: delivery.delivered_at,
      next_retry_at: delivery.next_retry_at,
      created_at: delivery.created_at,
      updated_at: delivery.updated_at
    }
  end
end
