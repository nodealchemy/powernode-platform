# frozen_string_literal: true

module Api
  module V1
    module Internal
      module Git
        # Internal API controller for broadcasting job logs from worker
        #
        # This controller is called by the worker service to broadcast
        # log chunks to connected WebSocket clients.
        #
        # Authentication: Internal API token (not user JWT)
        class JobLogsController < Api::V1::Internal::InternalBaseController
          # POST /api/v1/internal/git/job_logs/:id/broadcast
          #
          # Broadcast a log chunk to WebSocket subscribers
          #
          # Params:
          #   - content: Log content to broadcast
          #   - offset: Byte offset in the full log
          #   - is_complete: Whether this is the final chunk
          def broadcast
            job_id = params[:id]
            content = params[:content] || ""
            offset = params[:offset].to_i
            is_complete = ActiveModel::Type::Boolean.new.cast(params[:is_complete])

            GitJobLogsChannel.broadcast_log_chunk(
              job_id,
              content: content,
              offset: offset,
              is_complete: is_complete
            )

            # Update cached logs in database if needed
            update_cached_logs(job_id, content, offset, is_complete) if content.present?

            render_success(
              message: "Log chunk broadcast successfully",
              job_id: job_id,
              offset: offset,
              is_complete: is_complete
            )
          end

          # POST /api/v1/internal/git/job_logs/:id/error
          #
          # Broadcast a log error to WebSocket subscribers
          def error
            job_id = params[:id]
            error_message = params[:error] || "Unknown error"

            GitJobLogsChannel.broadcast_log_error(job_id, error: error_message)

            render_success(
              message: "Error broadcast successfully",
              job_id: job_id
            )
          end

          # POST /api/v1/internal/git/job_logs/:id/status
          #
          # Broadcast job status update
          def status
            job_id = params[:id]
            job_status = params[:status]
            conclusion = params[:conclusion]

            GitJobLogsChannel.broadcast_job_status(
              job_id,
              status: job_status,
              conclusion: conclusion
            )

            render_success(
              message: "Status broadcast successfully",
              job_id: job_id
            )
          end

          private

          def update_cached_logs(job_id, content, offset, is_complete)
            job = ::Devops::GitPipelineJob.find_by(id: job_id)
            return unless job

            # Append or replace logs based on offset
            if offset.zero?
              job.update(cached_logs: content)
            else
              existing = job.cached_logs || ""
              # Ensure we're appending at the right position
              if existing.bytesize <= offset
                job.update(cached_logs: existing + content)
              end
            end

            # Mark logs as complete if this is the final chunk
            job.update(logs_complete: true) if is_complete
          rescue StandardError => e
            Rails.logger.error "Failed to cache logs for job #{job_id}: #{e.message}"
          end
        end
      end
    end
  end
end
