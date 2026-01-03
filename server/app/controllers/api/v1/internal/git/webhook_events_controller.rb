# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Git
        class WebhookEventsController < InternalBaseController
          before_action :set_event

          # GET /api/v1/internal/git/webhook_events/:id
          def show
            render json: {
              success: true,
              data: serialize_event(@event)
            }
          end

          # PATCH /api/v1/internal/git/webhook_events/:id
          def update
            if @event.update(event_params)
              render json: { success: true, data: serialize_event(@event) }
            else
              render json: { success: false, error: @event.errors.full_messages.join(", ") },
                     status: :unprocessable_content
            end
          end

          # PATCH /api/v1/internal/git/webhook_events/:id/processing
          def processing
            unless @event.pending?
              render json: { success: false, error: "Event is not pending" },
                     status: :unprocessable_content
              return
            end

            @event.mark_processing!
            render json: { success: true, data: { status: @event.status } }
          end

          # PATCH /api/v1/internal/git/webhook_events/:id/processed
          def processed
            unless @event.processing?
              render json: { success: false, error: "Event is not processing" },
                     status: :unprocessable_content
              return
            end

            result = params[:processing_result]&.to_unsafe_h || {}
            @event.mark_processed!(result)
            render json: { success: true, data: { status: @event.status } }
          end

          # PATCH /api/v1/internal/git/webhook_events/:id/failed
          def failed
            error_message = params[:error_message] || "Unknown error"
            @event.mark_failed!(error_message)
            render json: { success: true, data: { status: @event.status } }
          end

          private

          def set_event
            @event = GitWebhookEvent.includes(:git_repository, :git_provider).find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render json: { success: false, error: "Webhook event not found" },
                   status: :not_found
          end

          def event_params
            params.permit(:status, :error_message, :retry_count, processing_result: {})
          end

          def serialize_event(event)
            {
              id: event.id,
              event_type: event.event_type,
              action: event.action,
              status: event.status,
              delivery_id: event.delivery_id,
              payload: event.payload,
              headers: event.headers,
              sender_username: event.sender_username,
              sender_id: event.sender_id,
              ref: event.ref,
              sha: event.sha,
              retry_count: event.retry_count,
              error_message: event.error_message,
              processing_result: event.processing_result,
              processed_at: event.processed_at&.iso8601,
              created_at: event.created_at.iso8601,
              repository: event.git_repository ? {
                id: event.git_repository.id,
                name: event.git_repository.name,
                full_name: event.git_repository.full_name,
                owner: event.git_repository.owner,
                default_branch: event.git_repository.default_branch,
                credential_id: event.git_repository.git_provider_credential_id
              } : nil,
              provider: {
                id: event.git_provider.id,
                name: event.git_provider.name,
                provider_type: event.git_provider.provider_type,
                api_base_url: event.git_provider.api_base_url
              },
              account_id: event.account_id
            }
          end
        end
      end
    end
  end
end
