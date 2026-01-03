# frozen_string_literal: true

# ActionCable channel for streaming Git pipeline job logs in real-time
#
# Stream naming: "git_job_logs:#{job_id}"
#
# Subscription params:
#   - repository_id: Git repository ID
#   - pipeline_id: Git pipeline ID
#   - job_id: Git pipeline job ID
#
# Events transmitted:
#   - connection_established: Sent on successful subscription
#   - log.chunk: Log content chunk with offset
#   - log.complete: Final log chunk, streaming complete
#   - log.error: Error fetching logs
#
class GitJobLogsChannel < ApplicationCable::Channel
  def subscribed
    @repository_id = params[:repository_id]
    @pipeline_id = params[:pipeline_id]
    @job_id = params[:job_id]

    # Validate parameters
    unless @repository_id.present? && @pipeline_id.present? && @job_id.present?
      reject
      return
    end

    # Verify access to the repository
    unless authorized_for_repository?
      reject
      return
    end

    # Subscribe to job-specific log stream
    stream_from stream_key

    # Confirm connection
    transmit({
      type: "connection_established",
      job_id: @job_id,
      message: "Connected to job logs stream",
      timestamp: Time.current.iso8601
    })

    # Queue log sync if job might have logs
    queue_log_sync_if_needed
  end

  def unsubscribed
    Rails.logger.info "GitJobLogsChannel: User #{current_user&.id} unsubscribed from job #{@job_id}"
    stop_all_streams
  end

  # Client can request a log refresh
  def refresh
    queue_log_sync_if_needed
  end

  class << self
    # Broadcast a log chunk to subscribers
    #
    # @param job_id [String] The job ID
    # @param content [String] Log content
    # @param offset [Integer] Byte offset in the full log
    # @param is_complete [Boolean] Whether this is the final chunk
    def broadcast_log_chunk(job_id, content:, offset: 0, is_complete: false)
      ActionCable.server.broadcast(
        stream_key_for(job_id),
        {
          type: is_complete ? "log.complete" : "log.chunk",
          job_id: job_id,
          payload: {
            content: content,
            offset: offset,
            is_complete: is_complete,
            chunk_size: content.bytesize
          },
          timestamp: Time.current.iso8601
        }
      )
    end

    # Broadcast a log error
    #
    # @param job_id [String] The job ID
    # @param error [String] Error message
    def broadcast_log_error(job_id, error:)
      ActionCable.server.broadcast(
        stream_key_for(job_id),
        {
          type: "log.error",
          job_id: job_id,
          payload: {
            error: error
          },
          timestamp: Time.current.iso8601
        }
      )
    end

    # Broadcast job status update
    #
    # @param job_id [String] The job ID
    # @param status [String] Job status
    # @param conclusion [String, nil] Job conclusion
    def broadcast_job_status(job_id, status:, conclusion: nil)
      ActionCable.server.broadcast(
        stream_key_for(job_id),
        {
          type: "job.status",
          job_id: job_id,
          payload: {
            status: status,
            conclusion: conclusion
          },
          timestamp: Time.current.iso8601
        }
      )
    end

    def stream_key_for(job_id)
      "git_job_logs:#{job_id}"
    end
  end

  private

  def stream_key
    self.class.stream_key_for(@job_id)
  end

  def authorized_for_repository?
    return false unless current_user

    # Find the repository
    repository = GitRepository.find_by(id: @repository_id)
    return false unless repository

    # Check if user has permission to view logs and belongs to the same account
    credential = repository.git_provider_credential
    return false unless credential

    current_user.account_id == credential.account_id &&
      current_user.has_permission?("git.pipelines.logs")
  end

  def queue_log_sync_if_needed
    job = GitPipelineJob.find_by(id: @job_id)
    return unless job

    # Only sync if job has started
    return if job.status == "pending" || job.status == "queued"

    # Queue the sync job via worker API
    begin
      WorkerApiClient.new.queue_git_job_logs_sync(
        @job_id,
        repository_id: @repository_id,
        pipeline_id: @pipeline_id,
        streaming: job.status == "running"
      )
    rescue StandardError => e
      Rails.logger.error "GitJobLogsChannel: Failed to queue log sync: #{e.message}"
    end
  end
end
