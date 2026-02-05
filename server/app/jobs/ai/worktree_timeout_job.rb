# frozen_string_literal: true

module Ai
  class WorktreeTimeoutJob < ApplicationJob
    queue_as :ai_execution

    # Check for timed-out worktrees across all active sessions
    def perform
      Ai::WorktreeSession.active_sessions.where.not(max_duration_seconds: nil).find_each do |session|
        check_session_timeouts(session)
      end
    end

    private

    def check_session_timeouts(session)
      timed_out = session.worktrees.active.where("timeout_at IS NOT NULL AND timeout_at < ?", Time.current)

      timed_out.find_each do |worktree|
        Rails.logger.warn "[WorktreeTimeout] Worktree #{worktree.branch_name} timed out"
        worktree.fail!(error_message: "Execution timed out", error_code: "TIMEOUT")
      end
    rescue StandardError => e
      Rails.logger.error "[WorktreeTimeout] Failed checking session #{session.id}: #{e.message}"
    end
  end
end
