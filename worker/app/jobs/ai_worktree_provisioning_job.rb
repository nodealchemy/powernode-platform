# frozen_string_literal: true

# AiWorktreeProvisioningJob - Provisions worktrees for an AI worktree session
#
# Fetches session data, starts the session, provisions each pending worktree,
# activates the session, then enqueues conflict detection.
class AiWorktreeProvisioningJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 2

  def execute(session_id)
    log_info("[WorktreeProvisioning] Starting provisioning", session_id: session_id)

    # Fetch session data
    session_response = api_client.get("/api/v1/internal/ai/worktree_sessions/#{session_id}")
    unless session_response['success']
      log_error("[WorktreeProvisioning] Failed to fetch session", nil, session_id: session_id)
      report_failure(session_id, "Failed to fetch session data", "SESSION_FETCH_FAILED")
      return
    end

    session = session_response['data']

    # Start the session
    start_response = api_client.post("/api/v1/internal/ai/worktree_sessions/#{session_id}/start")
    unless start_response['success']
      log_error("[WorktreeProvisioning] Failed to start session", nil,
        session_id: session_id, error: start_response['error'])
      report_failure(session_id, start_response['error'] || "Failed to start session", "SESSION_START_FAILED")
      return
    end

    # Provision each pending worktree
    worktrees = session['worktrees'] || []
    pending_worktrees = worktrees.select { |wt| wt['status'] == 'pending' }

    log_info("[WorktreeProvisioning] Provisioning worktrees",
      session_id: session_id, count: pending_worktrees.size)

    pending_worktrees.each do |worktree|
      worktree_id = worktree['id']
      provision_response = api_client.post(
        "/api/v1/internal/ai/worktree_sessions/#{session_id}/worktrees/#{worktree_id}/provision"
      )

      unless provision_response['success']
        log_error("[WorktreeProvisioning] Failed to provision worktree", nil,
          session_id: session_id, worktree_id: worktree_id, error: provision_response['error'])
        report_failure(session_id, "Failed to provision worktree #{worktree_id}", "WORKTREE_PROVISION_FAILED")
        return
      end

      log_info("[WorktreeProvisioning] Worktree provisioned",
        session_id: session_id, worktree_id: worktree_id)
    end

    # Activate the session
    activate_response = api_client.post("/api/v1/internal/ai/worktree_sessions/#{session_id}/activate")
    unless activate_response['success']
      log_error("[WorktreeProvisioning] Failed to activate session", nil,
        session_id: session_id, error: activate_response['error'])
      report_failure(session_id, activate_response['error'] || "Failed to activate session", "SESSION_ACTIVATE_FAILED")
      return
    end

    log_info("[WorktreeProvisioning] Session activated, enqueuing conflict detection",
      session_id: session_id)

    # Enqueue conflict detection
    AiConflictDetectionJob.perform_async(session_id)
  end

  private

  def report_failure(session_id, error_message, error_code)
    api_client.post("/api/v1/internal/ai/worktree_sessions/#{session_id}/fail_session", {
      error_message: error_message,
      error_code: error_code
    })
  rescue StandardError => e
    log_error("[WorktreeProvisioning] Failed to report failure", e, session_id: session_id)
  end
end
