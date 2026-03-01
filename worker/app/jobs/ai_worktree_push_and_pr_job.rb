# frozen_string_literal: true

# AiWorktreePushAndPrJob - Pushes worktree branches and creates pull requests
#
# Delegates to the server which has filesystem access for git push
# and API access for PR creation (Gitea/GitHub).
class AiWorktreePushAndPrJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 2

  def execute(session_id, options = {})
    options = options.is_a?(String) ? JSON.parse(options) : options

    log_info("[WorktreePushAndPr] Starting push and PR creation",
      session_id: session_id, options: options.keys)

    # Fetch session to verify status
    session_response = api_client.get("/api/v1/internal/ai/worktree_sessions/#{session_id}")
    unless session_response['success']
      log_error("[WorktreePushAndPr] Failed to fetch session", nil, session_id: session_id)
      return
    end

    session = session_response['data']
    unless session['status'] == 'completed'
      log_warn("[WorktreePushAndPr] Session not in completed status",
        session_id: session_id, status: session['status'])
      return
    end

    # Tell the server to push and create PRs
    pr_response = api_client.post(
      "/api/v1/internal/ai/worktree_sessions/#{session_id}/push_and_pr",
      options
    )

    unless pr_response['success']
      log_error("[WorktreePushAndPr] Push and PR creation failed", nil,
        session_id: session_id, error: pr_response['error'])
      return
    end

    log_info("[WorktreePushAndPr] Push and PR completed",
      session_id: session_id,
      pr_urls: pr_response.dig('data', 'pr_urls'))
  end
end
