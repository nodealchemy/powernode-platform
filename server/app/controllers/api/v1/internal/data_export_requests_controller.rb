# frozen_string_literal: true

module Api
  module V1
    module Internal
      class DataExportRequestsController < InternalBaseController
        before_action :require_internal_access
        before_action :set_export_request, only: [:show, :update]

        # GET /api/v1/internal/data_export_requests/:id
        def show
          render_success({ data_export_request: serialize_request(@export_request, include_details: true) })
        end

        # POST /api/v1/internal/data_export_requests
        def create
          @export_request = DataManagement::ExportRequest.new(export_request_params)
          @export_request.status = "pending"
          @export_request.requested_at = Time.current

          if @export_request.save
            # Queue processing job
            DataManagement::ExportProcessingJob.perform_later(@export_request.id)

            render_success({ data_export_request: serialize_request(@export_request) }, status: :created)
          else
            render_error(@export_request.errors.full_messages.join(", "), status: :unprocessable_entity)
          end
        end

        # PATCH/PUT /api/v1/internal/data_export_requests/:id
        def update
          case params[:action_type]
          when "start"
            start_export
          when "complete"
            complete_export
          when "fail"
            fail_export
          when "expire"
            expire_export
          else
            if @export_request.update(export_request_update_params)
              render_success({ data_export_request: serialize_request(@export_request) })
            else
              render_error(@export_request.errors.full_messages.join(", "), status: :unprocessable_entity)
            end
          end
        end

        private

        def set_export_request
          @export_request = DataManagement::ExportRequest.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          render_error("Data export request not found", status: :not_found)
        end

        def export_request_params
          params.require(:data_export_request).permit(
            :account_id, :user_id, :export_format, :requester_email,
            :requester_name, :include_attachments, :expires_after_hours,
            data_categories: [], metadata: {}
          )
        end

        def export_request_update_params
          params.require(:data_export_request).permit(:notes, metadata: {})
        end

        def start_export
          unless @export_request.pending?
            return render_error("Export is not pending", status: :unprocessable_entity)
          end

          @export_request.update!(
            status: "processing",
            started_at: Time.current
          )

          # Execute export in background
          DataManagement::ExportExecutionJob.perform_later(@export_request.id)

          render_success(
            { data_export_request: serialize_request(@export_request) },
            message: "Export started"
          )
        end

        def complete_export
          unless @export_request.processing?
            return render_error("Export is not processing", status: :unprocessable_entity)
          end

          expires_at = (@export_request.expires_after_hours || 168).hours.from_now

          @export_request.update!(
            status: "completed",
            completed_at: Time.current,
            file_path: params[:file_path],
            file_size_bytes: params[:file_size_bytes],
            download_url: params[:download_url],
            download_token: SecureRandom.urlsafe_base64(32),
            expires_at: expires_at,
            record_count: params[:record_count]
          )

          # Send completion notification with download link
          NotificationService.send_email(
            template: "data_export_ready",
            email: @export_request.requester_email,
            data: {
              request_id: @export_request.id,
              download_url: @export_request.download_url,
              expires_at: expires_at.iso8601,
              file_size: ActionController::Base.helpers.number_to_human_size(@export_request.file_size_bytes),
              record_count: @export_request.record_count
            }
          )

          render_success(
            { data_export_request: serialize_request(@export_request) },
            message: "Export completed"
          )
        end

        def fail_export
          unless @export_request.processing?
            return render_error("Export is not processing", status: :unprocessable_entity)
          end

          @export_request.update!(
            status: "failed",
            failed_at: Time.current,
            error_message: params[:error_message]
          )

          # Send failure notification
          NotificationService.send_email(
            template: "data_export_failed",
            email: @export_request.requester_email,
            data: {
              request_id: @export_request.id,
              error: "We encountered an issue generating your data export. Please try again or contact support."
            }
          )

          render_success(
            { data_export_request: serialize_request(@export_request) },
            message: "Export marked as failed"
          )
        end

        def expire_export
          unless @export_request.completed?
            return render_error("Export is not completed", status: :unprocessable_entity)
          end

          # Delete the exported file
          if @export_request.file_path.present?
            begin
              FileUtils.rm_rf(@export_request.file_path)
            rescue => e
              Rails.logger.warn "Failed to delete export file: #{e.message}"
            end
          end

          @export_request.update!(
            status: "expired",
            expired_at: Time.current,
            download_url: nil,
            download_token: nil
          )

          render_success(
            { data_export_request: serialize_request(@export_request) },
            message: "Export expired"
          )
        end

        def serialize_request(request, include_details: false)
          data = {
            id: request.id,
            request_id: request.request_id,
            status: request.status,
            account_id: request.account_id,
            user_id: request.user_id,
            export_format: request.export_format,
            requester_email: request.requester_email,
            requester_name: request.requester_name,
            data_categories: request.data_categories,
            include_attachments: request.include_attachments,
            requested_at: request.requested_at,
            created_at: request.created_at
          }

          if include_details
            data[:started_at] = request.started_at
            data[:completed_at] = request.completed_at
            data[:failed_at] = request.failed_at
            data[:expired_at] = request.expired_at
            data[:expires_at] = request.expires_at
            data[:file_size_bytes] = request.file_size_bytes
            data[:record_count] = request.record_count
            data[:download_url] = request.status == "completed" ? request.download_url : nil
            data[:error_message] = request.error_message
            data[:notes] = request.notes
            data[:metadata] = request.metadata
          end

          data
        end
      end
    end
  end
end
