# frozen_string_literal: true

module Api
  module V1
    module Internal
      module System
        # Internal API controller for system operation management
        class OperationsController < BaseController
          before_action :set_operation, only: %i[show update events]

          # GET /api/v1/internal/system/operations
          def index
            operations = ::System::Operation.all

            # Filter by status
            operations = operations.where(status: params[:status]) if params[:status].present?

            # Filter by operable
            if params[:operable_type].present? && params[:operable_id].present?
              operations = operations.where(
                operable_type: params[:operable_type],
                operable_id: params[:operable_id]
              )
            end

            # Limit results
            operations = operations.order(created_at: :desc).limit(params[:limit] || 100)

            render_success(
              data: {
                operations: operations.map { |o| operation_data(o) }
              }
            )
          end

          # GET /api/v1/internal/system/operations/:id
          def show
            render_success(data: operation_data(@operation))
          end

          # PATCH /api/v1/internal/system/operations/:id
          def update
            # Update status if provided
            if params[:status].present?
              case params[:status]
              when "running"
                @operation.start! if @operation.may_start?
              when "complete"
                @operation.complete! if @operation.may_complete?
              when "failed"
                @operation.fail!(params[:error_message]) if @operation.may_fail?
              when "aborted"
                @operation.abort! if @operation.may_abort?
              when "cancelled"
                @operation.cancel! if @operation.may_cancel?
              end
            end

            # Update progress if provided
            @operation.update_progress!(params[:progress].to_i) if params[:progress].present?

            # Update completed_at if provided
            if params[:completed_at].present?
              @operation.update(completed_at: Time.parse(params[:completed_at]))
            end

            render_success(data: operation_data(@operation.reload))
          rescue AASM::InvalidTransition => e
            render_error("Invalid operation state transition: #{e.message}", status: :unprocessable_entity)
          end

          # POST /api/v1/internal/system/operations/:id/events
          def events
            event_type = params[:event_type]&.to_sym || :info
            message = params[:message]
            timestamp = params[:timestamp] ? Time.parse(params[:timestamp]) : Time.current

            @operation.add_event(event_type, message, timestamp: timestamp)
            @operation.save!

            render_success(message: "Event added successfully")
          end

          private

          def set_operation
            @operation = ::System::Operation.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_not_found("Operation")
          end

          def operation_data(operation)
            {
              id: operation.id,
              command: operation.command,
              status: operation.status,
              progress: operation.progress,
              operable_type: operation.operable_type,
              operable_id: operation.operable_id,
              options: operation.options,
              events: operation.events,
              error_message: operation.error_message,
              scheduled_at: operation.scheduled_at,
              started_at: operation.started_at,
              completed_at: operation.completed_at,
              duration: operation.duration,
              created_at: operation.created_at,
              updated_at: operation.updated_at
            }
          end
        end
      end
    end
  end
end
