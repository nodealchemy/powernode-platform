# frozen_string_literal: true

module FileProcessing
  # Shared lifecycle for jobs that act on a FileManagement::ProcessingJob row.
  #
  # The server creates the row as "pending" (FileStorageService#queue_processing_job /
  # FileManagement::Object#queue_processing_job) and then dispatches by class-name
  # string. Nothing else moves that row — so a job that raises before reporting
  # leaves it pending FOREVER and the uploader is told nothing. Every arm below
  # therefore ends in a TERMINAL state (completed or failed).
  #
  # Server-side transitions are guarded: ProcessingJob#mark_completed! and
  # #mark_failed! both `return false unless processing?`, and the controller turns
  # that false into a 422. Hence the strict order: mark processing FIRST, then
  # work, then complete/fail. Reporting a failure that happened before the
  # processing transition cannot land, which is why #fail_before_processing walks
  # the row through processing on its way to failed.
  #
  # Endpoints used are the LIVE worker seam (/api/v1/worker/...) via
  # BackendApiClient, not the /api/v1/internal/file_processing_jobs paths that
  # FileProcessing::VirusScanJob calls — those have no route on the server.
  module ProcessingJobFlow
    # Raised by a job body when the external binary it needs is absent from this
    # worker image. Terminal and NOT re-raised: a Sidekiq retry lands on the same
    # host with the same missing binary, so retrying only burns the retry budget
    # before dying in the dead set with the row still pending.
    class ToolUnavailableError < StandardError; end

    # Fetch -> mark processing -> yield -> complete. The block receives
    # (job_record, file_object_id, file_object_hash) and returns the result_data
    # Hash recorded on the row.
    def run_processing_job(processing_job_id)
      if processing_job_id.nil? || processing_job_id.to_s.strip.empty?
        raise ArgumentError, 'processing_job_id is required'
      end

      record = fetch_processing_job(processing_job_id)
      file_object = record['file_object'] || {}
      file_object_id = record['file_object_id'] || file_object['id']

      if file_object_id.nil? || file_object_id.to_s.empty?
        log_error('Processing job has no file object', nil, processing_job_id: processing_job_id)
        fail_before_processing(processing_job_id, 'processing job has no file object')
        return { skipped: true, reason: 'no_file_object' }
      end

      begin_processing(processing_job_id, record)

      begin
        result = yield(record, file_object_id, file_object)
      rescue ToolUnavailableError => e
        log_warn('Required media tool unavailable on this worker',
                 processing_job_id: processing_job_id, error: e.message)
        report_failure(processing_job_id, e.message, 'reason' => 'tool_unavailable')
        return { skipped: true, reason: 'tool_unavailable' }
      end

      api_client.complete_file_processing_job(processing_job_id, result)
      { success: true, result: result }
    rescue StandardError => e
      log_error("#{self.class.name} failed", e, processing_job_id: processing_job_id)
      report_failure(processing_job_id, e.message)
      raise
    end

    # Raise ToolUnavailableError unless every named predicate on the service
    # answers true. `service.public_send(:ffprobe_available?)` is executed, not
    # inferred — the point is to find out before shelling out and getting ENOENT.
    def require_tools!(service, *predicates)
      missing = predicates.reject { |p| service.public_send(p) }
      return if missing.empty?

      tools = missing.map { |p| p.to_s.sub(/_available\?\z/, '') }.join(', ')
      raise ToolUnavailableError,
            "required tool(s) not installed on this worker: #{tools}"
    end

    private

    # Unwrap the render_success envelope ({"success":true,"data":{...}}).
    # BackendApiClient#get_file_processing_job returns the raw parsed body.
    def fetch_processing_job(processing_job_id)
      body = api_client.get_file_processing_job(processing_job_id)
      payload = body.is_a?(Hash) ? (body['data'] || body[:data] || body) : {}
      payload.is_a?(Hash) ? payload : {}
    end

    # Move the row pending -> processing. Skipped when the server already reports
    # it processing: on a Sidekiq RETRY the first attempt already made that
    # transition, and #start_processing! returns false for a non-pending row,
    # which the controller renders as 422 — so re-asserting it would make every
    # retry fail at the first API call and the row could never reach terminal.
    def begin_processing(processing_job_id, record)
      return if record['status'].to_s == 'processing'

      api_client.update_file_processing_job(processing_job_id, status: 'processing')
    rescue BackendApiClient::ApiError => e
      # 422 here means the row is no longer pending (concurrent worker, retry).
      # Any other status is a real transport problem and must surface.
      raise unless e.respond_to?(:status) && e.status == 422

      log_warn('Processing job was not pending; continuing',
               processing_job_id: processing_job_id, error: e.message)
    end

    # Report a terminal failure. Never raises — a job reporting a failure is
    # already on its error path and must not lose the original exception.
    def report_failure(processing_job_id, message, error_data = {})
      api_client.fail_file_processing_job(processing_job_id, message, error_data)
    rescue StandardError => e
      log_warn('Failed to report processing failure to server',
               processing_job_id: processing_job_id, error: e.message)
    end

    # Fail a row that has NOT yet been moved to processing. mark_failed! refuses
    # a pending row, so step it through processing first; otherwise the failure
    # report 422s and the row is left pending — the exact bug this job class
    # exists to remove.
    def fail_before_processing(processing_job_id, message)
      api_client.update_file_processing_job(processing_job_id, status: 'processing')
      report_failure(processing_job_id, message)
    rescue StandardError => e
      log_warn('Failed to fail processing job before processing',
               processing_job_id: processing_job_id, error: e.message)
    end
  end
end
