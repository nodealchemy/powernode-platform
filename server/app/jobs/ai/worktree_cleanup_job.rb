# frozen_string_literal: true

module Ai
  class WorktreeCleanupJob < ApplicationJob
    queue_as :ai_execution
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(session_id)
      session = Ai::WorktreeSession.find(session_id)

      # Release all file locks for this session
      session.file_locks.delete_all

      manager = Ai::Git::WorktreeManager.new(repository_path: session.repository_path)

      session.worktrees.where.not(status: "cleaned_up").find_each do |worktree|
        cleanup_worktree(manager, worktree, session)
      rescue StandardError => e
        Rails.logger.warn "[WorktreeCleanup] Failed to clean #{worktree.branch_name}: #{e.message}"
      end

      # Prune stale worktree references
      manager.prune

      Rails.logger.info "[WorktreeCleanup] Cleanup completed for session #{session_id}"
    end

    private

    def cleanup_worktree(manager, worktree, session)
      delete_branch = session.merge_config&.dig("delete_on_merge") != false

      manager.remove_worktree(
        worktree_path: worktree.worktree_path,
        branch_name: delete_branch ? worktree.branch_name : nil,
        force: true
      )

      worktree.mark_cleaned_up!
    end
  end
end
