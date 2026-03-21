# frozen_string_literal: true

module Api
  module V1
    module System
      module WorkerApi
        # Operation tracking and management for infrastructure workers
        # Handles operation lifecycle: create, start, progress, complete, fail
        class OperationsController < BaseController
          before_action :set_operation, only: [:show, :start, :progress, :complete, :fail, :add_event]

          # GET /api/v1/system/worker_api/operations
          # List operations for resources managed by this worker
          def index
            authorize_worker_permission!("system.operations.read")

            operations = worker_operations
            operations = apply_filters(operations)
            operations = paginate(operations.order(created_at: :desc))

            render_success(
              operations: operations.map { |o| serialize_operation(o) },
              meta: pagination_meta
            )
          end

          # GET /api/v1/system/worker_api/operations/pending
          # Get pending operations that need to be processed
          def pending
            authorize_worker_permission!("system.operations.read")

            operations = worker_operations.where(status: "pending")
                                          .order(created_at: :asc)
                                          .limit(params[:limit] || 10)

            render_success(
              operations: operations.map { |o| serialize_operation(o) },
              count: operations.size
            )
          end

          # GET /api/v1/system/worker_api/operations/:id
          def show
            authorize_worker_permission!("system.operations.read")
            render_success(operation: serialize_operation_full(@operation))
          end

          # POST /api/v1/system/worker_api/operations
          # Create new operation
          def create
            authorize_worker_permission!("system.operations.create")

            operable = find_operable
            return unless operable

            operation = operable.operations.build(operation_params)
            operation.account = operable.respond_to?(:account) ? operable.account : worker_account

            if operation.save
              render_success(operation: serialize_operation(operation), status: :created)
            else
              render_validation_error(operation)
            end
          end

          # POST /api/v1/system/worker_api/operations/:id/start
          # Mark operation as started
          def start
            authorize_worker_permission!("system.operations.manage")

            if @operation.pending?
              @operation.update!(
                status: "running",
                started_at: Time.current,
                progress: 0
              )
              add_operation_event("started", "Operation started by worker")

              render_success(operation: serialize_operation(@operation))
            else
              render_error("Operation cannot be started from #{@operation.status} state")
            end
          end

          # PUT /api/v1/system/worker_api/operations/:id/progress
          # Update operation progress
          def progress
            authorize_worker_permission!("system.operations.manage")

            unless @operation.running?
              return render_error("Can only update progress of running operations")
            end

            progress_value = params[:progress].to_i
            message = params[:message]

            @operation.update!(progress: progress_value)
            add_operation_event("progress", message) if message.present?

            render_success(
              operation: serialize_operation(@operation),
              progress: progress_value
            )
          end

          # POST /api/v1/system/worker_api/operations/:id/complete
          # Mark operation as completed
          def complete
            authorize_worker_permission!("system.operations.manage")

            unless @operation.running?
              return render_error("Only running operations can be completed")
            end

            result = params[:result] || {}

            @operation.update!(
              status: "complete",
              progress: 100,
              completed_at: Time.current,
              result: result
            )
            add_operation_event("completed", params[:message] || "Operation completed successfully")

            render_success(operation: serialize_operation(@operation))
          end

          # POST /api/v1/system/worker_api/operations/:id/fail
          # Mark operation as failed
          def fail
            authorize_worker_permission!("system.operations.manage")

            unless @operation.pending? || @operation.running?
              return render_error("Operation cannot be marked as failed from #{@operation.status} state")
            end

            error_message = params[:error_message] || "Operation failed"

            @operation.update!(
              status: "failed",
              completed_at: Time.current,
              error_message: error_message
            )
            add_operation_event("failed", error_message)

            render_success(operation: serialize_operation(@operation))
          end

          # POST /api/v1/system/worker_api/operations/:id/events
          # Add event to operation log
          def add_event
            authorize_worker_permission!("system.operations.manage")

            event_type = params[:event_type] || "info"
            message = params[:message]

            return render_error("Message is required") if message.blank?

            add_operation_event(event_type, message)

            render_success(
              operation: serialize_operation(@operation),
              event_added: true
            )
          end

          private

          def set_operation
            @operation = worker_operations.find(params[:id])
          rescue ActiveRecord::RecordNotFound
            render_record_not_found("Operation")
          end

          def worker_operations
            # Get operations for nodes managed by this worker
            node_ids = ::System::Node.where(worker: current_worker).pluck(:id)
            instance_ids = ::System::NodeInstance.where(node_id: node_ids).pluck(:id)

            ::System::Operation.where(
              "(operable_type = 'System::Node' AND operable_id IN (?)) OR " \
              "(operable_type = 'System::NodeInstance' AND operable_id IN (?))",
              node_ids,
              instance_ids
            )
          end

          def find_operable
            operable_type = params[:operable_type]
            operable_id = params[:operable_id]

            case operable_type
            when "System::Node", "node"
              ::System::Node.where(worker: current_worker).find(operable_id)
            when "System::NodeInstance", "instance"
              ::System::NodeInstance
                .joins(:node)
                .where(system_nodes: { worker_id: current_worker.id })
                .find(operable_id)
            else
              render_error("Invalid operable_type: #{operable_type}")
              nil
            end
          rescue ActiveRecord::RecordNotFound
            render_record_not_found(operable_type)
            nil
          end

          def operation_params
            params.require(:operation).permit(
              :command, :status, :progress,
              options: {}
            )
          end

          def apply_filters(scope)
            scope = scope.where(status: params[:status]) if params[:status].present?
            scope = scope.where(command: params[:command]) if params[:command].present?
            scope = scope.where("status IN (?)", %w[pending running]) if params[:active] == "true"
            scope = scope.where("status IN (?)", %w[complete failed]) if params[:finished] == "true"
            scope
          end

          def add_operation_event(event_type, message)
            events = @operation.events || []
            events << {
              type: event_type,
              message: message,
              timestamp: Time.current.iso8601,
              worker_id: current_worker.id
            }
            @operation.update!(events: events)
          end

          def serialize_operation(operation)
            {
              id: operation.id,
              command: operation.command,
              status: operation.status,
              progress: operation.progress,
              operable_type: operation.operable_type,
              operable_id: operation.operable_id,
              started_at: operation.started_at,
              completed_at: operation.completed_at,
              error_message: operation.error_message,
              created_at: operation.created_at,
              updated_at: operation.updated_at
            }
          end

          def serialize_operation_full(operation)
            serialize_operation(operation).merge(
              events: operation.events || [],
              options: operation.options,
              result: operation.result,
              duration_seconds: calculate_duration(operation)
            )
          end

          def calculate_duration(operation)
            return nil unless operation.started_at

            end_time = operation.completed_at || Time.current
            (end_time - operation.started_at).to_i
          end
        end
      end
    end
  end
end
