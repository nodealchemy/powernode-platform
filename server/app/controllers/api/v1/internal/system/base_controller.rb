# frozen_string_literal: true

module Api
  module V1
    module Internal
      module System
        # Base controller for internal System API endpoints accessed by worker service
        # These endpoints handle infrastructure management operations
        class BaseController < Api::V1::Internal::InternalBaseController
          private

          def set_account
            @account = Account.find(params[:account_id])
          rescue ActiveRecord::RecordNotFound
            render_not_found("Account")
          end

          def find_operation(operation_id)
            ::System::Operation.find(operation_id)
          rescue ActiveRecord::RecordNotFound
            nil
          end

          def update_operation_status(operation, status, error_message: nil)
            return unless operation

            case status
            when "running"
              operation.start! if operation.may_start?
            when "complete"
              operation.complete! if operation.may_complete?
            when "failed"
              operation.fail!(error_message) if operation.may_fail?
            when "aborted"
              operation.abort! if operation.may_abort?
            end
          end
        end
      end
    end
  end
end
