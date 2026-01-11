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

          # POST /api/v1/internal/git/webhook_events/:id/trigger_workflows
          # Find matching ::Devops::GitWorkflowTriggers and execute associated AI workflows
          def trigger_workflows
            triggered_workflows = []

            # Find all active git workflow triggers that match this event
            matching_triggers = find_matching_triggers

            matching_triggers.each do |git_trigger|
              begin
                # Trigger the workflow through the parent AI workflow trigger
                workflow_run = git_trigger.trigger!(@event)

                if workflow_run
                  triggered_workflows << {
                    git_trigger_id: git_trigger.id,
                    workflow_id: git_trigger.workflow.id,
                    workflow_name: git_trigger.workflow.name,
                    run_id: workflow_run.run_id
                  }

                  Rails.logger.info "[WEBHOOK_TRIGGER] Triggered workflow '#{git_trigger.workflow.name}' " \
                                   "from event #{@event.id} (#{@event.event_type})"
                end
              rescue StandardError => e
                Rails.logger.error "[WEBHOOK_TRIGGER] Failed to trigger workflow from git trigger " \
                                  "#{git_trigger.id}: #{e.message}"
                # Continue to next trigger even if one fails
              end
            end

            render json: {
              success: true,
              data: {
                triggered_count: triggered_workflows.count,
                triggered_workflows: triggered_workflows,
                event_id: @event.id,
                event_type: @event.event_type
              }
            }
          end

          private

          # Find ::Devops::GitWorkflowTriggers that match this webhook event
          def find_matching_triggers
            # Query for active triggers matching the event type
            triggers = ::Devops::GitWorkflowTrigger.active
                                        .for_event(@event.event_type)

            # Filter to repository-specific or global triggers
            if @event.git_repository_id.present?
              triggers = triggers.where(
                git_repository_id: [nil, @event.git_repository_id]
              )
            else
              triggers = triggers.global
            end

            # Further filter by matching event criteria
            triggers.includes(:trigger, trigger: :workflow)
                   .select { |trigger| trigger.matches_event?(@event) }
          end

          def set_event
            @event = ::Devops::GitWebhookEvent.includes(:repository, :git_provider).find(params[:id])
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
