# frozen_string_literal: true

module Api
  module V1
    module System
      class OperationsController < BaseController
        before_action :set_operation, only: [:show, :start, :complete, :fail, :abort, :cancel]

        # GET /api/v1/system/operations
        def index
          authorize_permission!('system.infra_operations.read')

          operations = current_account.system_operations
          operations = apply_filters(operations)
          operations = paginate(operations.includes(:operable, :initiated_by).recent)

          render_success(
            operations: operations.map { |o| ::System::OperationSerializer.new(o).as_json },
            meta: pagination_meta
          )
        end

        # GET /api/v1/system/operations/:id
        def show
          authorize_permission!('system.infra_operations.read')
          render_success(operation: ::System::OperationSerializer.new(@operation).as_json)
        end

        # POST /api/v1/system/operations
        def create
          authorize_permission!('system.infra_operations.create')

          operation = current_account.system_operations.build(operation_params)
          operation.initiated_by = current_user

          if operation.save
            render_success(operation: ::System::OperationSerializer.new(operation).as_json, status: :created)
          else
            render_validation_error(operation)
          end
        end

        # POST /api/v1/system/operations/:id/start
        def start
          authorize_permission!('system.infra_operations.control')

          if @operation.start!
            render_success(operation: ::System::OperationSerializer.new(@operation.reload).as_json)
          else
            render_error('Cannot start operation in current state', status: :unprocessable_entity)
          end
        end

        # POST /api/v1/system/operations/:id/complete
        def complete
          authorize_permission!('system.infra_operations.control')

          if @operation.complete!
            render_success(operation: ::System::OperationSerializer.new(@operation.reload).as_json)
          else
            render_error('Cannot complete operation in current state', status: :unprocessable_entity)
          end
        end

        # POST /api/v1/system/operations/:id/fail
        def fail
          authorize_permission!('system.infra_operations.control')

          if @operation.fail!(params[:error_message])
            render_success(operation: ::System::OperationSerializer.new(@operation.reload).as_json)
          else
            render_error('Cannot fail operation in current state', status: :unprocessable_entity)
          end
        end

        # POST /api/v1/system/operations/:id/abort
        def abort
          authorize_permission!('system.infra_operations.control')

          if @operation.abort!(params[:reason])
            render_success(operation: ::System::OperationSerializer.new(@operation.reload).as_json)
          else
            render_error('Cannot abort operation in current state', status: :unprocessable_entity)
          end
        end

        # POST /api/v1/system/operations/:id/cancel
        def cancel
          authorize_permission!('system.infra_operations.control')

          if @operation.cancel!(params[:reason])
            render_success(operation: ::System::OperationSerializer.new(@operation.reload).as_json)
          else
            render_error('Cannot cancel operation in current state', status: :unprocessable_entity)
          end
        end

        private

        def set_operation
          @operation = current_account.system_operations.find(params[:id])
        end

        def operation_params
          params.require(:operation).permit(
            :command, :description, :scheduled_at, :exclusive,
            :operable_type, :operable_id, options: {}
          )
        end

        def apply_filters(operations)
          operations = operations.by_status(params[:status]) if params[:status].present?
          operations = operations.by_command(params[:command]) if params[:command].present?
          operations = operations.active if params[:active] == 'true'
          operations = operations.finished if params[:finished] == 'true'
          operations = operations.exclusive if params[:exclusive] == 'true'
          operations
        end
      end
    end
  end
end
