# frozen_string_literal: true

module Ai
  class RunnerDispatchPollJob < ApplicationJob
    queue_as :default

    MAX_POLL_ATTEMPTS = 180 # 30 minutes at 10-second intervals

    def perform(session_id, poll_count: 0)
      session = Ai::WorktreeSession.find_by(id: session_id)
      return if session.nil? || session.terminal?

      if poll_count >= MAX_POLL_ATTEMPTS
        Rails.logger.warn "[RunnerDispatchPollJob] Timeout after #{poll_count} polls for session #{session_id}"
        timeout_active_dispatches(session)
        return
      end

      dispatch_service = Ai::RunnerDispatchService.new(account: session.account, session: session)
      active_dispatches = Ai::RunnerDispatch.where(worktree_session: session, status: %w[dispatched running])

      active_dispatches.each { |d| dispatch_service.sync_status(d) }

      if active_dispatches.reload.any? { |d| !%w[completed failed].include?(d.status) }
        self.class.set(wait: 10.seconds).perform_later(session_id, poll_count: poll_count + 1)
      else
        if session.all_worktrees_completed?
          session.begin_merge!
          Ai::MergeExecutionJob.perform_later(session.id)
        end
      end
    rescue StandardError => e
      Rails.logger.error "[RunnerDispatchPollJob] Error: #{e.message}"
    end

    private

    def timeout_active_dispatches(session)
      Ai::RunnerDispatch
        .where(worktree_session: session, status: %w[dispatched running])
        .find_each do |dispatch|
          dispatch.update!(status: "failed", completed_at: Time.current)
          dispatch.git_runner&.mark_available!
          dispatch.worktree&.fail!(
            error_message: "Workflow timed out after 30 minutes",
            error_code: "dispatch_timeout"
          )
        end
    end
  end
end
