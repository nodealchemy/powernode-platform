# frozen_string_literal: true

# AiMergeExecutionJob - Executes merge operations for a worktree session
#
# Tells the server to merge worktree branches. On success, optionally enqueues
# push/PR and cleanup jobs based on the server response.
class AiMergeExecutionJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 2

  def execute(session_id)
    log_info("[MergeExecution] Starting merge execution", session_id: session_id)

    merge_response = api_client.post(
      "/api/v1/internal/ai/worktree_sessions/#{session_id}/execute_merge"
    )

    unless merge_response['success']
      log_error("[MergeExecution] Merge failed", nil,
        session_id: session_id, error: merge_response['error'])
      report_failure(session_id, merge_response['error'] || "Merge execution failed", "MERGE_FAILED")
      return
    end

    data = merge_response['data'] || {}
    log_info("[MergeExecution] Merge completed",
      session_id: session_id, merge_status: data['merge_status'])

    # Enqueue follow-up jobs based on server response
    if data['auto_pr']
      log_info("[MergeExecution] Enqueuing push and PR job", session_id: session_id)
      AiWorktreePushAndPrJob.perform_async(session_id, data['pr_options'] || {})
    end

    if data['auto_cleanup']
      log_info("[MergeExecution] Enqueuing cleanup job", session_id: session_id)
      AiWorktreeCleanupJob.perform_async(session_id)
    end
  end

  private

  def report_failure(session_id, error_message, error_code)
    api_client.post("/api/v1/internal/ai/worktree_sessions/#{session_id}/fail_session", {
      error_message: error_message,
      error_code: error_code
    })
  rescue StandardError => e
    log_error("[MergeExecution] Failed to report failure", e, session_id: session_id)
  end
end
