# frozen_string_literal: true

# AiConflictDetectionJob - Detects conflicts between worktree branches
#
# Simple dispatch job that asks the server to run conflict detection
# for all worktrees in a session.
class AiConflictDetectionJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 2

  def execute(session_id)
    log_info("[ConflictDetection] Starting conflict detection", session_id: session_id)

    response = api_client.post(
      "/api/v1/internal/ai/worktree_sessions/#{session_id}/detect_conflicts"
    )

    if response['success']
      data = response['data'] || {}
      log_info("[ConflictDetection] Detection completed",
        session_id: session_id,
        conflicts_found: data['conflicts_found'],
        conflict_count: data['conflict_count'])
    else
      log_error("[ConflictDetection] Detection failed", nil,
        session_id: session_id, error: response['error'])
    end
  end
end
