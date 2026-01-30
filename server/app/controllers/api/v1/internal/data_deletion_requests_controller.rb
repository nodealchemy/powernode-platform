# frozen_string_literal: true

module Api
  module V1
    module Internal
      class DataDeletionRequestsController < InternalBaseController
        before_action :set_deletion_request, only: [:show, :update]

        # GET /api/v1/internal/data_deletion_requests/:id
        def show
          render_success({ data_deletion_request: serialize_request(@deletion_request, include_details: true) })
        end

        # POST /api/v1/internal/data_deletion_requests
        def create
          @deletion_request = DataManagement::DeletionRequest.new(deletion_request_params)
          @deletion_request.status = "pending"

          if @deletion_request.save
            # Queue processing job
            DataManagement::DeletionProcessingJob.perform_later(@deletion_request.id)

            render_success({ data_deletion_request: serialize_request(@deletion_request) }, status: :created)
          else
            render_error(@deletion_request.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/internal/data_deletion_requests/:id
        def update
          case params[:action_type]
          when "approve"
            approve_request
          when "reject"
            reject_request
          when "execute"
            execute_request
          when "complete"
            complete_request
          else
            if @deletion_request.update(deletion_request_update_params)
              render_success({ data_deletion_request: serialize_request(@deletion_request) })
            else
              render_error(@deletion_request.errors.full_messages.join(", "), status: :unprocessable_entity)
            end
          end
        end

        private

        def set_deletion_request
          @deletion_request = DataManagement::DeletionRequest.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Data deletion request not found", status: :not_found)
        end

        def deletion_request_params
          params.require(:data_deletion_request).permit(
            :account_id, :user_id, :deletion_type, :reason,
            data_types_to_delete: [], data_types_to_retain: [], metadata: {}
          )
        end

        def deletion_request_update_params
          params.require(:data_deletion_request).permit(metadata: {})
        end

        def approve_request
          unless @deletion_request.pending?
            return render_error("Request is not pending", status: :unprocessable_entity)
          end

          @deletion_request.update!(
            status: "approved",
            approved_at: Time.current,
            processed_by_id: params[:processed_by_id]
          )

          # Send approval notification
          NotificationService.send_email(
            template: "data_deletion_approved",
            user_id: @deletion_request.user_id,
            data: {
              request_id: @deletion_request.id
            }
          )

          render_success(
            { data_deletion_request: serialize_request(@deletion_request) },
            message: "Deletion request approved"
          )
        end

        def reject_request
          unless @deletion_request.pending? || @deletion_request.approved?
            return render_error("Request cannot be rejected", status: :unprocessable_entity)
          end

          if params[:reason].blank?
            return render_error("Rejection reason is required", status: :unprocessable_entity)
          end

          @deletion_request.update!(
            status: "rejected",
            rejection_reason: params[:reason],
            completed_at: Time.current,
            processed_by_id: params[:rejected_by_id]
          )

          # Send rejection notification
          NotificationService.send_email(
            template: "data_deletion_rejected",
            user_id: @deletion_request.user_id,
            data: {
              request_id: @deletion_request.id,
              reason: params[:reason]
            }
          )

          render_success(
            { data_deletion_request: serialize_request(@deletion_request) },
            message: "Deletion request rejected"
          )
        end

        def execute_request
          unless @deletion_request.approved?
            return render_error("Request must be approved before execution", status: :unprocessable_entity)
          end

          @deletion_request.update!(
            status: "processing",
            processing_started_at: Time.current
          )

          # Execute deletion in background
          DataManagement::DeletionExecutionJob.perform_later(@deletion_request.id)

          render_success(
            { data_deletion_request: serialize_request(@deletion_request) },
            message: "Deletion execution started"
          )
        end

        def complete_request
          unless @deletion_request.processing?
            return render_error("Request is not processing", status: :unprocessable_entity)
          end

          @deletion_request.update!(
            status: "completed",
            completed_at: Time.current,
            deletion_log: params[:deletion_log] || []
          )

          # Send completion notification
          NotificationService.send_email(
            template: "data_deletion_completed",
            user_id: @deletion_request.user_id,
            data: {
              request_id: @deletion_request.id,
              completed_at: @deletion_request.completed_at.iso8601
            }
          )

          render_success(
            { data_deletion_request: serialize_request(@deletion_request) },
            message: "Deletion completed"
          )
        end

        def serialize_request(request, include_details: false)
          data = {
            id: request.id,
            deletion_type: request.deletion_type,
            status: request.status,
            account_id: request.account_id,
            user_id: request.user_id,
            data_types_to_delete: request.data_types_to_delete,
            data_types_to_retain: request.data_types_to_retain,
            created_at: request.created_at
          }

          if include_details
            data[:reason] = request.reason
            data[:approved_at] = request.approved_at
            data[:processed_by_id] = request.processed_by_id
            data[:rejection_reason] = request.rejection_reason
            data[:processing_started_at] = request.processing_started_at
            data[:completed_at] = request.completed_at
            data[:grace_period_ends_at] = request.grace_period_ends_at
            data[:deletion_log] = request.deletion_log
            data[:retention_log] = request.retention_log
            data[:error_message] = request.error_message
            data[:metadata] = request.metadata
          end

          data
        end
      end
    end
  end
end
