# frozen_string_literal: true

module Ai
  class RunnerDispatchPollJob < ApplicationJob
    queue_as :default

    def perform(session_id)
      session = Ai::WorktreeSession.find_by(id: session_id)
      return if session.nil? || session.terminal?

      dispatch_service = Ai::RunnerDispatchService.new(account: session.account, session: session)
      active_dispatches = Ai::RunnerDispatch.where(worktree_session: session, status: %w[dispatched running])

      active_dispatches.each { |d| dispatch_service.sync_status(d) }

      if active_dispatches.reload.any? { |d| !%w[completed failed].include?(d.status) }
        self.class.set(wait: 10.seconds).perform_later(session_id)
      else
        if session.all_worktrees_completed?
          session.begin_merge!
          Ai::MergeExecutionJob.perform_later(session.id)
        end
      end
    rescue StandardError => e
      Rails.logger.error "[RunnerDispatchPollJob] Error: #{e.message}"
    end
  end
end
