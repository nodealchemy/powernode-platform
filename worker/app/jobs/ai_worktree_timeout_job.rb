# frozen_string_literal: true

# AiWorktreeTimeoutJob - Periodic job to check for timed-out worktree sessions
#
# Scheduled job that asks the server to check all active sessions for timeouts.
# The server handles identifying and failing timed-out sessions.
class AiWorktreeTimeoutJob < BaseJob
  include AiJobsConcern

  sidekiq_options queue: 'ai_execution', retry: 1

  def execute(*_args)
    log_info("[WorktreeTimeout] Checking for timed-out worktree sessions")

    response = api_client.post("/api/v1/internal/ai/worktree_sessions/check_timeouts")

    if response['success']
      timed_out = response.dig('data', 'timed_out_count') || 0
      log_info("[WorktreeTimeout] Timeout check completed", timed_out_count: timed_out)
    else
      log_error("[WorktreeTimeout] Timeout check failed: #{response['error']}")
    end
  end
end
