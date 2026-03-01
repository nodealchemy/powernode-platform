# frozen_string_literal: true

# AiWorktreeCleanupJob - Cleans up worktrees for a completed/failed session
#
# Tells the server to clean up filesystem worktrees and mark the session
# as cleaned up. The server handles the actual filesystem operations.
class AiWorktreeCleanupJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 3

  def execute(session_id)
    log_info("[WorktreeCleanup] Starting cleanup", session_id: session_id)

    # Fetch session to verify it exists and check status
    session_response = api_client.get("/api/v1/internal/ai/worktree_sessions/#{session_id}")
    unless session_response['success']
      log_error("[WorktreeCleanup] Failed to fetch session", nil, session_id: session_id)
      return
    end

    session = session_response['data']
    log_info("[WorktreeCleanup] Session status: #{session['status']}", session_id: session_id)

    # Tell the server to perform cleanup
    cleanup_response = api_client.post("/api/v1/internal/ai/worktree_sessions/#{session_id}/cleanup")
    unless cleanup_response['success']
      log_error("[WorktreeCleanup] Cleanup failed", nil,
        session_id: session_id, error: cleanup_response['error'])
      return
    end

    log_info("[WorktreeCleanup] Cleanup completed",
      session_id: session_id,
      worktrees_cleaned: cleanup_response.dig('data', 'worktrees_cleaned'))
  end
end
