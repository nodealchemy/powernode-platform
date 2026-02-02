# frozen_string_literal: true

module Api
  module V1
    class WebhookEventsController < ApplicationController
      before_action :authenticate_request
      before_action :require_webhook_permission
      before_action :set_webhook_event, only: [ :show, :update, :processing, :processed, :failed ]

      # GET /api/v1/webhook_events/:id
      def show
        render_success({ webhook_event: serialize_event(@event, include_details: true) })
      end

      # PATCH/PUT /api/v1/webhook_events/:id
      def update
        if @event.update(event_update_params)
          render_success({ webhook_event: serialize_event(@event) })
        else
          render_error(@event.errors.full_messages.join(", "), status: :unprocessable_content)
        end
      end

      # PATCH /api/v1/webhook_events/:id/processing
      def processing
        unless @event.status == "pending"
          return render_error("Event is not pending", status: :unprocessable_content)
        end

        merged_metadata = parse_metadata(@event.metadata).merge("processing_started_at" => Time.current.iso8601)

        @event.update!(
          status: "processing",
          retry_count: @event.retry_count + 1,
          metadata: merged_metadata.to_json
        )

        render_success({ webhook_event: serialize_event(@event) })
      end

      # PATCH /api/v1/webhook_events/:id/processed
      def processed
        unless @event.status == "processing"
          return render_error("Event is not processing", status: :unprocessable_content)
        end

        current_metadata = parse_metadata(@event.metadata)
        processing_started = current_metadata["processing_started_at"]
        duration_ms = nil
        if processing_started
          duration_ms = ((Time.current - Time.parse(processing_started)) * 1000).to_i rescue nil
        end

        merged_metadata = current_metadata.merge(
          "response_code" => params[:response_code],
          "delivery_duration_ms" => duration_ms
        ).compact

        @event.update!(
          status: "processed",
          processed_at: Time.current,
          metadata: merged_metadata.to_json
        )

        render_success({ webhook_event: serialize_event(@event) })
      end

      # PATCH /api/v1/webhook_events/:id/failed
      def failed
        unless @event.status == "processing"
          return render_error("Event is not processing", status: :unprocessable_content)
        end

        max_attempts = 5
        retriable = @event.retry_count < max_attempts

        new_status = retriable ? "pending" : "failed"

        next_retry_at = retriable ? calculate_next_retry(@event) : nil

        current_metadata = parse_metadata(@event.metadata)
        merged_metadata = current_metadata.merge(
          "last_error_at" => Time.current.iso8601,
          "response_code" => params[:response_code],
          "next_retry_at" => next_retry_at&.iso8601
        ).compact

        @event.update!(
          status: new_status,
          error_message: params[:error],
          metadata: merged_metadata.to_json
        )

        render_success({ webhook_event: serialize_event(@event) })
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
        params.permit(metadata: {})
      end

      def calculate_next_retry(event)
        base_delays = [ 1.minute, 5.minutes, 30.minutes, 2.hours, 8.hours ]
        delay = base_delays[[ event.retry_count - 1, base_delays.length - 1 ].min]
        jitter = rand(0..(delay.to_i * 0.1)).seconds
        Time.current + delay + jitter
      end

      def parse_metadata(raw)
        return {} if raw.blank?
        JSON.parse(raw)
      rescue JSON::ParserError
        {}
      end

      def serialize_event(event, include_details: false)
        data = {
          id: event.id,
          event_id: event.event_id,
          event_type: event.event_type,
          status: event.status,
          provider: event.provider,
          retry_count: event.retry_count,
          created_at: event.created_at,
          processed_at: event.processed_at
        }

        if include_details
          data[:payload] = event.payload
          data[:error_message] = event.error_message
          data[:metadata] = parse_metadata(event.metadata)
          data[:occurred_at] = event.occurred_at
          data[:external_id] = event.external_id
        end

        data
      end
    end
  end
end
