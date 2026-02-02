# frozen_string_literal: true

module Api
  module V1
    module Webhooks
      class EventsController < ApplicationController
        before_action :authenticate_request
        before_action :require_webhook_permission
        before_action :set_event, only: [ :show, :update, :processing, :processed, :failed ]

        # GET /api/v1/webhooks/events/:id
        def show
          render_success({ webhook_event: serialize_event(@event, include_details: true) })
        end

        # PATCH/PUT /api/v1/webhooks/events/:id
        def update
          if @event.update(event_update_params)
            render_success({ webhook_event: serialize_event(@event) })
          else
            render_error(@event.errors.full_messages.join(", "), status: :unprocessable_content)
          end
        end

        # POST /api/v1/webhooks/events/:id/processing
        def processing
          unless @event.pending?
            return render_error("Event is not pending", status: :unprocessable_content)
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

        # POST /api/v1/webhooks/events/:id/processed
        def processed
          unless @event.processing?
            return render_error("Event is not processing", status: :unprocessable_content)
          end

          @event.update!(
            status: "processed",
            processed_at: Time.current,
            response_code: params[:response_code],
            response_body: params[:response_body]&.truncate(10_000)
          )

          render_success(
            { webhook_event: serialize_event(@event) },
            message: "Event processed successfully"
          )
        end

        # POST /api/v1/webhooks/events/:id/failed
        def failed
          unless @event.processing?
            return render_error("Event is not processing", status: :unprocessable_content)
          end

          @event.update!(
            status: @event.retriable? ? "pending" : "failed",
            last_error: params[:error],
            last_error_at: Time.current,
            response_code: params[:response_code],
            response_body: params[:response_body]&.truncate(10_000),
            next_retry_at: @event.retriable? ? calculate_next_retry(@event) : nil
          )

          if @event.status == "pending"
            # Schedule retry
            WebhookDeliveryJob.perform_at(@event.next_retry_at, @event.id)
          end

          render_success(
            { webhook_event: serialize_event(@event) },
            message: @event.failed? ? "Event permanently failed" : "Event will be retried"
          )
        end

        private

        def require_webhook_permission
          return if current_user.has_permission?("webhooks.manage")
          render_error("Insufficient permissions", status: :forbidden)
        end

        def set_event
          @event = WebhookEvent.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Webhook event not found", status: :not_found)
        end

        def event_update_params
          params.require(:webhook_event).permit(:notes, metadata: {})
        end

        def calculate_next_retry(event)
          # Exponential backoff: 1min, 5min, 30min, 2hr, 8hr
          delays = [ 1.minute, 5.minutes, 30.minutes, 2.hours, 8.hours ]
          delay = delays[[ event.attempts - 1, delays.length - 1 ].min]
          Time.current + delay
        end

        def serialize_event(event, include_details: false)
          data = {
            id: event.id,
            event_id: event.event_id,
            event_type: event.event_type,
            status: event.status,
            webhook_endpoint_id: event.webhook_endpoint_id,
            account_id: event.account_id,
            attempts: event.attempts,
            max_attempts: event.max_attempts,
            created_at: event.created_at,
            processed_at: event.processed_at
          }

          if include_details
            data[:payload] = event.payload
            data[:response_code] = event.response_code
            data[:response_body] = event.response_body
            data[:last_error] = event.last_error
            data[:last_error_at] = event.last_error_at
            data[:next_retry_at] = event.next_retry_at
            data[:processing_started_at] = event.processing_started_at
            data[:delivery_duration_ms] = event.delivery_duration_ms
            data[:idempotency_key] = event.idempotency_key
            data[:notes] = event.notes
            data[:metadata] = event.metadata
          end

          data
        end
      end
    end
  end
end
