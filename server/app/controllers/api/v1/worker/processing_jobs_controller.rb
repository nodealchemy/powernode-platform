# frozen_string_literal: true

module Api
  module V1
    module Worker
      # Controller for file processing job operations
      # Allows workers to retrieve, update, complete, and fail processing jobs
      class ProcessingJobsController < WorkerBaseController
        before_action :set_processing_job, only: %i[show update]

        # GET /api/v1/worker/processing_jobs/:id
        def show
          render_success({
            id: @job.id,
            job_type: @job.job_type,
            status: @job.status,
            file_object_id: @job.file_object_id,
            priority: @job.priority,
            job_parameters: @job.job_parameters,
            retry_count: @job.retry_count,
            max_retries: @job.max_retries,
            started_at: @job.started_at&.iso8601,
            completed_at: @job.completed_at&.iso8601,
            created_at: @job.created_at.iso8601,
            file_object: @job.file_object ? {
              id: @job.file_object.id,
              filename: @job.file_object.filename,
              content_type: @job.file_object.content_type,
              file_size: @job.file_object.file_size,
              storage_path: @job.file_object.storage_path
            } : nil
          })
        end

        # PATCH /api/v1/worker/processing_jobs/:id
        def update
          update_params = {}

          # Handle status updates
          if params[:status]
            case params[:status]
            when "processing"
              unless @job.start_processing!
                return render_error("Cannot start processing: invalid status", status: :unprocessable_content)
              end
            when "completed"
              result_data = params[:result_data] || {}
              unless @job.mark_completed!(result_data)
                return render_error("Cannot mark as completed: invalid status", status: :unprocessable_content)
              end
            when "failed"
              error_message = params.dig(:error_details, :error_message) || "Processing failed"
              error_data = params[:error_details] || {}
              unless @job.mark_failed!(error_message, error_data)
                return render_error("Cannot mark as failed: invalid status", status: :unprocessable_content)
              end
            else
              return render_validation_error("Invalid status", field: "status")
            end
          end

          # Handle other updates
          allowed_updates = params.permit(:priority, result_data: {}, error_details: {}, metadata: {})
          @job.update(allowed_updates)

          render_success({ job: @job.job_summary })

        rescue StandardError => e
          Rails.logger.error "[ProcessingJobsController] Update failed: #{e.message}"
          render_error("Job update failed", status: :internal_server_error)
        end

        private

        def set_processing_job
          @job = FileManagement::ProcessingJob.find_by(id: params[:id])

          unless @job
            render_error("Processing job not found", status: :not_found)
          end
        end
      end
    end
  end
end
