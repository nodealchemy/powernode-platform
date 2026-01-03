# frozen_string_literal: true

module Git
  # Job to fetch and stream job logs from Git providers
  #
  # This job fetches logs from GitHub/GitLab/Gitea APIs and broadcasts
  # them to connected WebSocket clients via the internal API.
  #
  # For running jobs, it can poll periodically to stream new log content.
  #
  # @example Queue from Rails
  #   WorkerApiClient.new.queue_git_job_logs_sync(
  #     job_id,
  #     repository_id: repo_id,
  #     pipeline_id: pipeline_id,
  #     streaming: true
  #   )
  class JobLogsSyncJob < BaseJob
    # Maximum log size to fetch (10MB)
    MAX_LOG_SIZE = 10 * 1024 * 1024

    # Chunk size for broadcasting (8KB)
    CHUNK_SIZE = 8 * 1024

    # Polling interval for streaming logs (seconds)
    STREAMING_INTERVAL = 3

    # Maximum streaming duration (5 minutes)
    MAX_STREAMING_DURATION = 5 * 60

    def execute(job_id, options = {})
      @job_id = job_id
      @repository_id = options["repository_id"] || options[:repository_id]
      @pipeline_id = options["pipeline_id"] || options[:pipeline_id]
      @streaming = options["streaming"] || options[:streaming]
      @last_offset = 0

      logger.info "Starting log sync for job #{@job_id}, streaming: #{@streaming}"

      # Fetch job details
      job_response = fetch_job_details
      return broadcast_error("Job not found") unless job_response

      @provider_type = job_response["provider_type"]
      @external_job_id = job_response["external_id"]
      @credential_id = job_response["credential_id"]

      if @streaming && job_response["status"] == "running"
        stream_logs_with_polling
      else
        fetch_and_broadcast_logs
      end
    end

    private

    def fetch_job_details
      response = backend_api.get("/api/v1/git/repositories/#{@repository_id}/pipelines/#{@pipeline_id}/jobs/#{@job_id}")
      response["data"]["job"] if response["success"]
    rescue StandardError => e
      logger.error "Failed to fetch job details: #{e.message}"
      nil
    end

    def stream_logs_with_polling
      start_time = Time.now
      previous_content = ""

      loop do
        # Check if we've exceeded max streaming duration
        if Time.now - start_time > MAX_STREAMING_DURATION
          logger.info "Max streaming duration reached for job #{@job_id}"
          break
        end

        # Fetch current logs
        logs_content = fetch_logs_from_provider
        break unless logs_content

        # Check for new content
        if logs_content.bytesize > previous_content.bytesize
          new_content = logs_content[previous_content.bytesize..]
          broadcast_log_chunks(new_content, offset: previous_content.bytesize)
          previous_content = logs_content
        end

        # Check if job is still running
        job_status = check_job_status
        unless job_status == "running"
          # Final fetch and broadcast
          final_logs = fetch_logs_from_provider
          if final_logs && final_logs.bytesize > previous_content.bytesize
            new_content = final_logs[previous_content.bytesize..]
            broadcast_log_chunks(new_content, offset: previous_content.bytesize, is_final: true)
          else
            broadcast_complete
          end
          break
        end

        sleep STREAMING_INTERVAL
      end
    end

    def fetch_and_broadcast_logs
      logs_content = fetch_logs_from_provider
      return broadcast_error("Failed to fetch logs") unless logs_content

      broadcast_log_chunks(logs_content, offset: 0, is_final: true)
    end

    def fetch_logs_from_provider
      # Use the backend API to fetch logs (it handles provider-specific logic)
      response = backend_api.get(
        "/api/v1/git/repositories/#{@repository_id}/pipelines/#{@pipeline_id}/jobs/#{@job_id}/logs"
      )

      if response["success"]
        response["data"]["logs"]
      else
        logger.error "Failed to fetch logs: #{response['error']}"
        nil
      end
    rescue StandardError => e
      logger.error "Error fetching logs: #{e.message}"
      nil
    end

    def check_job_status
      response = backend_api.get(
        "/api/v1/git/repositories/#{@repository_id}/pipelines/#{@pipeline_id}/jobs/#{@job_id}"
      )
      response["data"]["job"]["status"] if response["success"]
    rescue StandardError
      nil
    end

    def broadcast_log_chunks(content, offset: 0, is_final: false)
      return if content.nil? || content.empty?

      # Split into chunks for large logs
      chunks = content.scan(/.{1,#{CHUNK_SIZE}}/m)
      current_offset = offset

      chunks.each_with_index do |chunk, index|
        is_last_chunk = is_final && index == chunks.length - 1

        backend_api.post(
          "/api/v1/internal/git/job_logs/#{@job_id}/broadcast",
          {
            content: chunk,
            offset: current_offset,
            is_complete: is_last_chunk
          }
        )

        current_offset += chunk.bytesize
        @last_offset = current_offset

        # Small delay between chunks to avoid overwhelming clients
        sleep 0.01 if chunks.length > 1
      end

      logger.info "Broadcast #{chunks.length} chunks, total bytes: #{content.bytesize}"
    end

    def broadcast_complete
      backend_api.post(
        "/api/v1/internal/git/job_logs/#{@job_id}/broadcast",
        {
          content: "",
          offset: @last_offset,
          is_complete: true
        }
      )
    end

    def broadcast_error(message)
      backend_api.post(
        "/api/v1/internal/git/job_logs/#{@job_id}/error",
        { error: message }
      )
    end
  end
end
