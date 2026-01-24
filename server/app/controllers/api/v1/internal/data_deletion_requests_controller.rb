# frozen_string_literal: true

module Api
  module V1
    module Internal
      class DataDeletionRequestsController < InternalBaseController
        before_action :require_internal_access
        before_action :set_deletion_request, only: [:show, :update]

        # GET /api/v1/internal/data_deletion_requests/:id
        def show
          render_success({ data_deletion_request: serialize_request(@deletion_request, include_details: true) })
        end

        # POST /api/v1/internal/data_deletion_requests
        def create
          @deletion_request = DataManagement::DeletionRequest.new(deletion_request_params)
          @deletion_request.status = "pending"
          @deletion_request.requested_at = Time.current

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
            :account_id, :user_id, :request_type, :reason, :requester_email,
            :requester_name, :verification_token, :scheduled_for,
            data_categories: [], metadata: {}
          )
        end

        def deletion_request_update_params
          params.require(:data_deletion_request).permit(
            :notes, :scheduled_for, metadata: {}
          )
        end

        def approve_request
          unless @deletion_request.pending?
            return render_error("Request is not pending", status: :unprocessable_entity)
          end

          @deletion_request.update!(
            status: "approved",
            approved_at: Time.current,
            approved_by_id: params[:approved_by_id]
          )

          # Send approval notification
          NotificationService.send_email(
            template: "data_deletion_approved",
            email: @deletion_request.requester_email,
            data: {
              request_id: @deletion_request.id,
              scheduled_for: @deletion_request.scheduled_for&.iso8601
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
            rejected_at: Time.current,
            rejected_by_id: params[:rejected_by_id]
          )

          # Send rejection notification
          NotificationService.send_email(
            template: "data_deletion_rejected",
            email: @deletion_request.requester_email,
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
            started_at: Time.current
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
            deleted_records_count: params[:deleted_records_count],
            deletion_summary: params[:deletion_summary]
          )

          # Send completion notification
          NotificationService.send_email(
            template: "data_deletion_completed",
            email: @deletion_request.requester_email,
            data: {
              request_id: @deletion_request.id,
              deleted_count: @deletion_request.deleted_records_count,
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
            request_id: request.request_id,
            request_type: request.request_type,
            status: request.status,
            account_id: request.account_id,
            user_id: request.user_id,
            requester_email: request.requester_email,
            requester_name: request.requester_name,
            data_categories: request.data_categories,
            requested_at: request.requested_at,
            scheduled_for: request.scheduled_for,
            created_at: request.created_at
          }

          if include_details
            data[:reason] = request.reason
            data[:approved_at] = request.approved_at
            data[:approved_by_id] = request.approved_by_id
            data[:rejected_at] = request.rejected_at
            data[:rejected_by_id] = request.rejected_by_id
            data[:rejection_reason] = request.rejection_reason
            data[:started_at] = request.started_at
            data[:completed_at] = request.completed_at
            data[:deleted_records_count] = request.deleted_records_count
            data[:deletion_summary] = request.deletion_summary
            data[:notes] = request.notes
            data[:metadata] = request.metadata
          end

          data
        end
      end
    end
  end
end
