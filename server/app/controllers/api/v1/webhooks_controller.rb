# frozen_string_literal: true

class Api::V1::WebhooksController < ApplicationController
  before_action :require_admin_access
  before_action :find_webhook, only: [:show, :update, :destroy, :test, :toggle_status]

  # GET /api/v1/webhooks
  def index
    webhooks = WebhookEndpoint.includes(:webhook_events)
                              .order(:created_at)
                              .page(params[:page] || 1)
                              .per(params[:per_page] || 20)

    render json: {
      success: true,
      data: {
        webhooks: webhooks.map { |webhook| webhook_summary(webhook) },
        pagination: {
          current_page: webhooks.current_page,
          per_page: webhooks.limit_value,
          total_pages: webhooks.total_pages,
          total_count: webhooks.total_count
        },
        stats: webhook_stats
      }
    }, status: :ok
  end

  # GET /api/v1/webhooks/:id
  def show
    render json: {
      success: true,
      data: detailed_webhook_data(@webhook)
    }, status: :ok
  end

  # POST /api/v1/webhooks
  def create
    webhook = WebhookEndpoint.new(webhook_params)
    webhook.created_by = current_user

    if webhook.save
      # Log webhook creation
      log_webhook_action('webhook_created', webhook)

      render json: {
        success: true,
        message: 'Webhook endpoint created successfully',
        data: detailed_webhook_data(webhook)
      }, status: :created
    else
      render json: {
        success: false,
        error: 'Failed to create webhook endpoint',
        details: webhook.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/webhooks/:id
  def update
    if @webhook.update(webhook_params)
      log_webhook_action('webhook_updated', @webhook)

      render json: {
        success: true,
        message: 'Webhook endpoint updated successfully',
        data: detailed_webhook_data(@webhook)
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to update webhook endpoint',
        details: @webhook.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # DELETE /api/v1/webhooks/:id
  def destroy
    webhook_data = webhook_summary(@webhook)
    
    if @webhook.destroy
      log_webhook_action('webhook_deleted', @webhook, webhook_data)

      render json: {
        success: true,
        message: 'Webhook endpoint deleted successfully'
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to delete webhook endpoint',
        details: @webhook.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/webhooks/:id/test
  def test
    test_payload = generate_test_payload(params[:event_type] || 'test.webhook')
    
    begin
      response = WebhookService.deliver_webhook(@webhook, test_payload, 'test.webhook')
      
      # Log test attempt
      log_webhook_action('webhook_test', @webhook, {
        event_type: 'test.webhook',
        response_status: response[:status],
        response_time: response[:response_time],
        success: response[:success]
      })
      
      render json: {
        success: true,
        message: 'Webhook test completed',
        data: {
          webhook_id: @webhook.id,
          test_payload: test_payload,
          response: response
        }
      }, status: :ok
    rescue => e
      log_webhook_action('webhook_test_failed', @webhook, {
        event_type: 'test.webhook',
        error: e.message
      })
      
      render json: {
        success: false,
        error: 'Webhook test failed',
        details: e.message
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/webhooks/:id/toggle_status
  def toggle_status
    new_status = @webhook.active? ? 'inactive' : 'active'
    
    if @webhook.update(status: new_status)
      log_webhook_action('webhook_status_changed', @webhook, {
        old_status: @webhook.status_was,
        new_status: new_status
      })

      render json: {
        success: true,
        message: "Webhook endpoint #{new_status == 'active' ? 'activated' : 'deactivated'}",
        data: webhook_summary(@webhook)
      }, status: :ok
    else
      render json: {
        success: false,
        error: 'Failed to update webhook status',
        details: @webhook.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/webhooks/events
  def available_events
    render json: {
      success: true,
      data: {
        events: WebhookEndpoint.available_event_types,
        categories: WebhookEndpoint.event_categories
      }
    }, status: :ok
  end

  # GET /api/v1/webhooks/deliveries
  def delivery_history
    webhook_id = params[:webhook_id]
    deliveries_query = WebhookDelivery.includes(:webhook_endpoint)
                                      .order(created_at: :desc)
    
    deliveries_query = deliveries_query.where(webhook_endpoint_id: webhook_id) if webhook_id.present?
    
    deliveries = deliveries_query.page(params[:page] || 1)
                                .per(params[:per_page] || 50)

    render json: {
      success: true,
      data: {
        deliveries: deliveries.map { |delivery| delivery_summary(delivery) },
        pagination: {
          current_page: deliveries.current_page,
          per_page: deliveries.limit_value,
          total_pages: deliveries.total_pages,
          total_count: deliveries.total_count
        }
      }
    }, status: :ok
  end

  # GET /api/v1/webhooks/stats
  def stats
    render json: {
      success: true,
      data: detailed_webhook_stats
    }, status: :ok
  end

  # POST /api/v1/webhooks/retry_failed
  def retry_failed
    failed_deliveries = WebhookDelivery.failed
                                      .where(created_at: 24.hours.ago..Time.current)
                                      .includes(:webhook_endpoint)
    
    retry_count = 0
    failed_deliveries.each do |delivery|
      if delivery.webhook_endpoint.active? && delivery.can_retry?
        WebhookRetryJob.perform_later(delivery.id)
        retry_count += 1
      end
    end
    
    render json: {
      success: true,
      message: "Queued #{retry_count} webhook deliveries for retry",
      data: {
        retry_count: retry_count,
        total_failed: failed_deliveries.count
      }
    }, status: :ok
  end

  private

  def require_admin_access
    unless current_user.owner? || current_user.admin?
      render json: {
        success: false,
        error: "Access denied: Admin privileges required"
      }, status: :forbidden
    end
  end

  def find_webhook
    @webhook = WebhookEndpoint.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: 'Webhook endpoint not found'
    }, status: :not_found
  end

  def webhook_params
    params.require(:webhook).permit(
      :url, :description, :status, :secret_token, :content_type,
      :timeout_seconds, :retry_limit, :retry_backoff,
      event_types: []
    )
  end

  def webhook_summary(webhook)
    {
      id: webhook.id,
      url: webhook.url,
      description: webhook.description,
      status: webhook.status,
      event_types: webhook.event_types || [],
      content_type: webhook.content_type,
      timeout_seconds: webhook.timeout_seconds,
      retry_limit: webhook.retry_limit,
      created_at: webhook.created_at.iso8601,
      updated_at: webhook.updated_at.iso8601,
      last_delivery_at: webhook.last_delivery_at&.iso8601,
      success_count: webhook.success_count,
      failure_count: webhook.failure_count,
      created_by: webhook.created_by ? {
        id: webhook.created_by.id,
        email: webhook.created_by.email
      } : nil
    }
  end

  def detailed_webhook_data(webhook)
    webhook_summary(webhook).merge({
      secret_token: webhook.secret_token,
      retry_backoff: webhook.retry_backoff,
      recent_deliveries: webhook.webhook_deliveries
                               .order(created_at: :desc)
                               .limit(10)
                               .map { |delivery| delivery_summary(delivery) },
      delivery_stats: {
        total_deliveries: webhook.webhook_deliveries.count,
        success_rate: webhook.success_rate,
        average_response_time: webhook.average_response_time,
        last_success_at: webhook.last_success_at&.iso8601,
        last_failure_at: webhook.last_failure_at&.iso8601
      }
    })
  end

  def delivery_summary(delivery)
    {
      id: delivery.id,
      webhook_endpoint_id: delivery.webhook_endpoint_id,
      event_type: delivery.event_type,
      status: delivery.status,
      http_status: delivery.http_status,
      response_time_ms: delivery.response_time_ms,
      attempt_count: delivery.attempt_count,
      next_retry_at: delivery.next_retry_at&.iso8601,
      created_at: delivery.created_at.iso8601,
      completed_at: delivery.completed_at&.iso8601,
      error_message: delivery.error_message,
      webhook_endpoint: delivery.webhook_endpoint ? {
        id: delivery.webhook_endpoint.id,
        url: delivery.webhook_endpoint.url
      } : nil
    }
  end

  def webhook_stats
    {
      total_endpoints: WebhookEndpoint.count,
      active_endpoints: WebhookEndpoint.active.count,
      inactive_endpoints: WebhookEndpoint.inactive.count,
      total_deliveries_today: WebhookDelivery.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).count,
      successful_deliveries_today: WebhookDelivery.successful.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).count,
      failed_deliveries_today: WebhookDelivery.failed.where(created_at: Date.current.beginning_of_day..Date.current.end_of_day).count
    }
  end

  def detailed_webhook_stats
    webhook_stats.merge({
      most_active_endpoints: WebhookEndpoint.joins(:webhook_deliveries)
                                           .group('webhook_endpoints.url')
                                           .order('count_id DESC')
                                           .limit(5)
                                           .count(:id),
      event_type_distribution: WebhookDelivery.where(created_at: 7.days.ago..Time.current)
                                             .group(:event_type)
                                             .count,
      daily_delivery_trend: WebhookDelivery.where(created_at: 7.days.ago..Time.current)
                                          .group_by_day(:created_at)
                                          .count,
      average_response_times: WebhookDelivery.successful
                                           .where(created_at: 24.hours.ago..Time.current)
                                           .average(:response_time_ms),
      retry_statistics: {
        total_retries: WebhookDelivery.where('attempt_count > 1').count,
        pending_retries: WebhookDelivery.pending_retry.count,
        max_retries_reached: WebhookDelivery.max_retries_reached.count
      }
    })
  end

  def generate_test_payload(event_type)
    {
      event: {
        id: SecureRandom.uuid,
        type: event_type,
        created_at: Time.current.iso8601,
        test: true
      },
      data: {
        id: SecureRandom.uuid,
        attributes: {
          message: "This is a test webhook delivery",
          timestamp: Time.current.iso8601,
          environment: Rails.env
        }
      }
    }
  end

  def log_webhook_action(action, webhook, metadata = {})
    AuditLog.create!(
      user: current_user,
      account: current_user.account,
      action: action,
      resource_type: 'WebhookEndpoint',
      resource_id: webhook.id,
      source: 'admin_panel',
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: metadata.merge({
        webhook_url: webhook.url,
        event_types: webhook.event_types
      })
    )
  end
end