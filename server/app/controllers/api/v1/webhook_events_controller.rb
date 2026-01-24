# frozen_string_literal: true

module Api
  module V1
    class WebhookEventsController < ApplicationController
      before_action :authenticate_request
      before_action :require_webhook_permission
      before_action :set_webhook_event, only: [:show, :update, :processing, :processed, :failed]

      # GET /api/v1/webhook_events
      def index
        @events = current_account.webhook_events
                                 .includes(:webhook_endpoint)
                                 .order(created_at: :desc)

        @events = @events.where(status: params[:status]) if params[:status].present?
        @events = @events.where(event_type: params[:event_type]) if params[:event_type].present?
        @events = @events.where(webhook_endpoint_id: params[:endpoint_id]) if params[:endpoint_id].present?

        if params[:since].present?
          @events = @events.where("created_at >= ?", Time.parse(params[:since]))
        end

        @events = paginate(@events)

        render_success(
          { webhook_events: @events.map { |e| serialize_event(e) } },
          meta: pagination_meta
        )
      end

      # GET /api/v1/webhook_events/:id
      def show
        render_success({ webhook_event: serialize_event(@event, include_details: true) })
      end

      # PATCH/PUT /api/v1/webhook_events/:id
      def update
        if @event.update(event_update_params)
          render_success({ webhook_event: serialize_event(@event) })
        else
          render_error(@event.errors.full_messages.join(", "), status: :unprocessable_entity)
        end
      end

      # POST /api/v1/webhook_events/:id/processing
      def processing
        unless @event.pending?
          return render_error("Event is not pending", status: :unprocessable_entity)
        end

        @event.update!(
          status: "processing",
          processing_started_at: Time.current,
          attempts: @event.attempts + 1
        )

        render_success(
          { webhook_event: serialize_event(@event) },
          message: "Event marked as processing"
        )
      end

      # POST /api/v1/webhook_events/:id/processed
      def processed
        unless @event.processing?
          return render_error("Event is not processing", status: :unprocessable_entity)
        end

        duration_ms = nil
        if @event.processing_started_at
          duration_ms = ((Time.current - @event.processing_started_at) * 1000).to_i
        end

        @event.update!(
          status: "processed",
          processed_at: Time.current,
          response_code: params[:response_code],
          response_body: params[:response_body]&.truncate(10_000),
          delivery_duration_ms: duration_ms
        )

        # Update endpoint statistics
        update_endpoint_stats(@event.webhook_endpoint, success: true)

        render_success(
          { webhook_event: serialize_event(@event) },
          message: "Event processed successfully"
        )
      end

      # POST /api/v1/webhook_events/:id/failed
      def failed
        unless @event.processing?
          return render_error("Event is not processing", status: :unprocessable_entity)
        end

        max_attempts = @event.max_attempts || 5
        retriable = @event.attempts < max_attempts

        new_status = retriable ? "pending" : "failed"

        @event.update!(
          status: new_status,
          last_error: params[:error],
          last_error_at: Time.current,
          response_code: params[:response_code],
          response_body: params[:response_body]&.truncate(10_000),
          next_retry_at: retriable ? calculate_next_retry(@event) : nil
        )

        # Update endpoint statistics
        update_endpoint_stats(@event.webhook_endpoint, success: false)

        if retriable
          # Schedule retry job
          WebhookDeliveryJob.perform_at(@event.next_retry_at, @event.id)
        else
          # Send failure notification if configured
          notify_webhook_failure(@event)
        end

        render_success(
          { webhook_event: serialize_event(@event) },
          message: new_status == "failed" ? "Event permanently failed after #{max_attempts} attempts" : "Event will be retried"
        )
      end

      private

      def require_webhook_permission
        return if current_user.has_permission?("webhooks.manage")
        render_error("Insufficient permissions", status: :forbidden)
      end

      def set_webhook_event
        @event = current_account.webhook_events.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render_error("Webhook event not found", status: :not_found)
      end

      def event_update_params
        params.require(:webhook_event).permit(:notes, metadata: {})
      end

      def calculate_next_retry(event)
        # Exponential backoff with jitter
        base_delays = [1.minute, 5.minutes, 30.minutes, 2.hours, 8.hours]
        delay = base_delays[[event.attempts - 1, base_delays.length - 1].min]
        jitter = rand(0..(delay.to_i * 0.1)).seconds
        Time.current + delay + jitter
      end

      def update_endpoint_stats(endpoint, success:)
        return unless endpoint

        if success
          endpoint.increment!(:success_count)
          endpoint.update(last_success_at: Time.current)
        else
          endpoint.increment!(:failure_count)
          endpoint.update(last_failure_at: Time.current)

          # Check if endpoint should be disabled
          check_endpoint_health(endpoint)
        end
      end

      def check_endpoint_health(endpoint)
        # Disable endpoint if failure rate is too high
        recent_events = endpoint.webhook_events.where("created_at >= ?", 1.hour.ago)
        return if recent_events.count < 10

        failure_rate = recent_events.where(status: "failed").count.to_f / recent_events.count
        if failure_rate > 0.8
          endpoint.update!(status: "disabled", disabled_reason: "High failure rate (#{(failure_rate * 100).round}%)")

          NotificationService.send_to_account(
            account_id: endpoint.account_id,
            template: "webhook_endpoint_disabled",
            message: "Webhook endpoint '#{endpoint.name}' has been disabled due to high failure rate",
            notification_type: "warning",
            data: { endpoint_id: endpoint.id, failure_rate: failure_rate }
          )
        end
      end

      def notify_webhook_failure(event)
        NotificationService.send_to_account(
          account_id: event.account_id,
          template: "webhook_delivery_failed",
          message: "Webhook delivery failed after #{event.attempts} attempts for event #{event.event_type}",
          notification_type: "error",
          data: {
            event_id: event.id,
            event_type: event.event_type,
            endpoint_id: event.webhook_endpoint_id,
            last_error: event.last_error
          }
        )
      end

      def serialize_event(event, include_details: false)
        data = {
          id: event.id,
          event_id: event.event_id,
          event_type: event.event_type,
          status: event.status,
          endpoint: event.webhook_endpoint ? {
            id: event.webhook_endpoint.id,
            name: event.webhook_endpoint.name,
            url: event.webhook_endpoint.url
          } : nil,
          attempts: event.attempts,
          max_attempts: event.max_attempts || 5,
          response_code: event.response_code,
          created_at: event.created_at,
          processed_at: event.processed_at
        }

        if include_details
          data[:payload] = event.payload
          data[:response_body] = event.response_body
          data[:last_error] = event.last_error
          data[:last_error_at] = event.last_error_at
          data[:next_retry_at] = event.next_retry_at
          data[:processing_started_at] = event.processing_started_at
          data[:delivery_duration_ms] = event.delivery_duration_ms
          data[:idempotency_key] = event.idempotency_key
          data[:headers_sent] = event.headers_sent
          data[:notes] = event.notes
          data[:metadata] = event.metadata
        end

        data
      end

      def paginate(scope)
        page = (params[:page] || 1).to_i
        per_page = (params[:per_page] || 20).to_i.clamp(1, 100)
        @total_count = scope.count
        @page = page
        @per_page = per_page
        scope.offset((page - 1) * per_page).limit(per_page)
      end

      def pagination_meta
        {
          current_page: @page,
          per_page: @per_page,
          total_count: @total_count,
          total_pages: (@total_count.to_f / @per_page).ceil
        }
      end
    end
  end
end
