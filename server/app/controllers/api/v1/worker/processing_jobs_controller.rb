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
          # Handle status updates
          if params[:status]
            case params[:status]
            when "processing"
              unless @job.start_processing!
                return render_error("Cannot start processing: invalid status", status: :unprocessable_content)
              end
            when "completed"
              unless @job.mark_completed!(nested_hash(:result_data))
                return render_error("Cannot mark as completed: invalid status", status: :unprocessable_content)
              end
            when "failed"
              error_message = params.dig(:error_details, :error_message) || "Processing failed"
              unless @job.mark_failed!(error_message, nested_hash(:error_details))
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

        # ProcessingJob#mark_completed!/#mark_failed! merge this into a plain
        # jsonb Hash. Handing them the raw ActionController::Parameters made
        # Hash#merge call #to_hash on an UNPERMITTED Parameters, which raises
        # ActionController::UnfilteredParameters — swallowed by the rescue below
        # into a 500, so EVERY worker completion and failure report failed and
        # the row never left "processing". These are worker-authored free-form
        # result/error payloads with no fixed schema, so permit! is the correct
        # call: the keys are not attributes, they are opaque jsonb content.
        def nested_hash(key)
          value = params[key]
          return {} if value.blank?
          return value.to_h if value.is_a?(Hash)

          value.respond_to?(:permit!) ? value.permit!.to_h : {}
        end

        def set_processing_job
          @job = account_scoped(FileManagement::ProcessingJob).find_by(id: params[:id])

          unless @job
            render_error("Processing job not found", status: :not_found)
          end
        end
      end
    end
  end
end
