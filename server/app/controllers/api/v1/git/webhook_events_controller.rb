# frozen_string_literal: true

module Api
  module V1
    module Git
      class WebhookEventsController < ApplicationController
        before_action :set_event, only: %i[show retry]
        before_action :validate_permissions

        # GET /api/v1/git/webhook_events
        def index
          events = current_user.account.git_webhook_events
                     .includes(:repository, :git_provider)

          # Filters
          events = events.by_event_type(params[:event_type]) if params[:event_type].present?
          events = events.where(status: params[:status]) if params[:status].present?
          events = events.for_repository(params[:repository_id]) if params[:repository_id].present?

          if params[:provider_id].present?
            events = events.where(git_provider_id: params[:provider_id])
          end

          # Date range
          if params[:since].present?
            events = events.where("created_at >= ?", Time.parse(params[:since]))
          end

          if params[:until].present?
            events = events.where("created_at <= ?", Time.parse(params[:until]))
          end

          # Pagination
          page = [params[:page].to_i, 1].max
          per_page = [[params[:per_page].to_i, 100].min, 20].max
          total = events.count
          events = events.order(created_at: :desc).offset((page - 1) * per_page).limit(per_page)

          render_success({
            items: events.map { |e| serialize_event(e) },
            pagination: {
              current_page: page,
              per_page: per_page,
              total_pages: (total.to_f / per_page).ceil,
              total_count: total
            }
          })
        end

        # GET /api/v1/git/webhook_events/:id
        def show
          render_success({ event: serialize_event_detail(@event) })
        end

        # POST /api/v1/git/webhook_events/:id/retry
        def retry
          if @event.retry!
            render_success({ message: "Event queued for retry", event: serialize_event(@event.reload) })
          else
            render_error("Event cannot be retried", status: :unprocessable_content)
          end
        end

        # GET /api/v1/git/webhook_events/stats
        def stats
          events = current_user.account.git_webhook_events

          # Filter by provider if specified
          if params[:provider_id].present?
            events = events.where(git_provider_id: params[:provider_id])
          end

          # Filter by days if specified
          if params[:days].present?
            days = params[:days].to_i
            events = events.where("created_at >= ?", days.days.ago)
          end

          render_success({
            stats: {
              total_events: events.count,
              pending_count: events.pending.count,
              processing_count: events.processing.count,
              processed_count: events.processed.count,
              failed_count: events.failed.count,
              today_count: events.where("created_at >= ?", Time.current.beginning_of_day).count,
              success_rate: calculate_success_rate(events)
            }
          })
        end

        private

        def set_event
          @event = current_user.account.git_webhook_events
                     .includes(:repository, :git_provider)
                     .find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Webhook event not found", status: :not_found)
        end

        def validate_permissions
          require_permission("git.webhooks.read")
        end

        def calculate_success_rate(events)
          total_completed = events.where(status: %w[processed failed]).count
          return 0 if total_completed.zero?

          processed = events.processed.count
          (processed.to_f / total_completed * 100).round(2)
        end

        def serialize_event(event)
          {
            id: event.id,
            event_type: event.event_type,
            action: event.action,
            status: event.status,
            delivery_id: event.delivery_id,
            sender_username: event.sender_username,
            ref: event.ref,
            branch_name: event.branch_name,
            sha: event.sha,
            short_sha: event.sha&.first(7),
            summary: event.payload_summary,
            retry_count: event.retry_count,
            retryable: event.retryable?,
            processed_at: event.processed_at&.iso8601,
            created_at: event.created_at.iso8601,
            repository: event.git_repository ? {
              id: event.git_repository.id,
              name: event.git_repository.name,
              full_name: event.git_repository.full_name
            } : nil,
            provider: {
              id: event.git_provider.id,
              name: event.git_provider.name,
              type: event.git_provider.provider_type
            }
          }
        end

        def serialize_event_detail(event)
          serialize_event(event).merge(
            payload: event.payload,
            headers: event.headers,
            error_message: event.error_message,
            processing_result: event.processing_result,
            sender_info: event.sender_info
          )
        end
      end
    end
  end
end
