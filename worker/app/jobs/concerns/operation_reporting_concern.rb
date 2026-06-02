# frozen_string_literal: true

# Shared operation-reporting helpers for System jobs that drive a server-side
# operation record (provision, sync, build, commit, image, volume, control, ...).
#
# These helpers patch/post against /api/v1/internal/system/operations/:id and
# were duplicated verbatim across the system jobs; they live here so there is a
# single implementation to evolve. track_operation wraps the common
# running -> work -> complete/failed lifecycle in one block.
#
# Depends on BaseJob#api_client, #with_api_retry and #log_warn, so include it
# only in `< BaseJob` job classes.
module OperationReportingConcern
  extend ActiveSupport::Concern

  private

  # Run a block as a tracked operation: mark it running, yield, then mark it
  # complete on success — or failed (with the exception message) if the block
  # raises, re-raising so Sidekiq retry/dead handling still applies. Returns the
  # block's value. Every status call no-ops when operation_id is nil, so this is
  # safe to wrap around work that may or may not have an operation to report to.
  def track_operation(operation_id)
    update_operation_status(operation_id, 'running')
    result = yield
    update_operation_status(operation_id, 'complete')
    result
  rescue StandardError => e
    update_operation_status(operation_id, 'failed', error_message: e.message)
    raise
  end

  # Patch the operation's status, stamping completed_at on terminal states.
  def update_operation_status(operation_id, status, error_message: nil)
    return unless operation_id

    with_api_retry do
      api_client.patch("/api/v1/internal/system/operations/#{operation_id}", {
        status: status,
        error_message: error_message,
        completed_at: %w[complete failed].include?(status) ? Time.current.iso8601 : nil
      }.compact)
    end
  rescue StandardError => e
    log_warn('Failed to update operation status', operation_id: operation_id, error: e.message)
  end

  # Patch the operation's progress percentage.
  def update_operation_progress(operation_id, progress)
    return unless operation_id

    with_api_retry do
      api_client.patch("/api/v1/internal/system/operations/#{operation_id}", {
        progress: progress
      })
    end
  rescue StandardError => e
    log_warn('Failed to update operation progress', operation_id: operation_id, error: e.message)
  end

  # Append a timestamped event to the operation's event log.
  def add_operation_event(operation_id, event_type, message)
    return unless operation_id

    with_api_retry do
      api_client.post("/api/v1/internal/system/operations/#{operation_id}/events", {
        event_type: event_type,
        message: message,
        timestamp: Time.current.iso8601
      })
    end
  rescue StandardError => e
    log_warn('Failed to add operation event', operation_id: operation_id, error: e.message)
  end
end
