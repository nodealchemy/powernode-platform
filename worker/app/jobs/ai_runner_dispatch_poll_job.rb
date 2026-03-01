# frozen_string_literal: true

# AiRunnerDispatchPollJob - Polls dispatch status for worktree runner executions
#
# Periodically checks if all dispatched runner tasks have completed.
# Re-enqueues itself with a delay until all dispatches finish or timeout.
class AiRunnerDispatchPollJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 1

  MAX_POLL_ATTEMPTS = 180

  def execute(session_id, options = {})
    options = options.is_a?(String) ? JSON.parse(options) : options
    poll_count = options['poll_count'] || 0

    log_info("[RunnerDispatchPoll] Polling dispatch status",
      session_id: session_id, poll_count: poll_count, max: MAX_POLL_ATTEMPTS)

    # Check for timeout
    if poll_count >= MAX_POLL_ATTEMPTS
      log_warn("[RunnerDispatchPoll] Max poll attempts reached, timing out dispatches",
        session_id: session_id, poll_count: poll_count)

      api_client.post("/api/v1/internal/ai/worktree_sessions/#{session_id}/timeout_dispatches")
      return
    end

    # Check dispatch status
    status_response = api_client.get(
      "/api/v1/internal/ai/worktree_sessions/#{session_id}/dispatch_status"
    )

    unless status_response['success']
      log_error("[RunnerDispatchPoll] Failed to fetch dispatch status", nil,
        session_id: session_id)
      return
    end

    data = status_response['data'] || {}
    active_count = data['active_dispatches'] || 0
    completed_count = data['completed_dispatches'] || 0
    total_count = data['total_dispatches'] || 0

    log_info("[RunnerDispatchPoll] Dispatch status",
      session_id: session_id, active: active_count,
      completed: completed_count, total: total_count)

    if active_count > 0
      # Still active dispatches - re-enqueue with delay
      self.class.perform_in(10, session_id, { 'poll_count' => poll_count + 1 })
    else
      # All dispatches complete - enqueue merge execution
      log_info("[RunnerDispatchPoll] All dispatches completed, enqueuing merge execution",
        session_id: session_id)
      AiMergeExecutionJob.perform_async(session_id)
    end
  end
end
