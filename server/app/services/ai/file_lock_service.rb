# frozen_string_literal: true

module Ai
  class FileLockService
    attr_reader :session

    def initialize(session:)
      @session = session
    end

    # Acquire locks on files for a worktree
    def acquire(worktree:, file_paths:, lock_type: "exclusive", ttl_seconds: nil)
      return { success: true, locks: [] } if file_paths.blank?

      conflicts = check_conflicts(worktree: worktree, file_paths: file_paths)
      return { success: false, conflicts: conflicts } if conflicts.any?

      expires_at = ttl_seconds ? Time.current + ttl_seconds.seconds : nil
      now = Time.current

      locks = file_paths.map do |path|
        session.file_locks.create!(
          worktree: worktree,
          account: session.account,
          file_path: path,
          lock_type: lock_type,
          acquired_at: now,
          expires_at: expires_at
        )
      end

      { success: true, locks: locks.map { |l| lock_summary(l) } }
    rescue ActiveRecord::RecordNotUnique => e
      { success: false, error: "File already locked", details: e.message }
    rescue StandardError => e
      { success: false, error: e.message }
    end

    # Release all locks for a worktree
    def release(worktree:)
      count = session.file_locks.where(worktree: worktree).delete_all
      { success: true, released: count }
    end

    # Release specific file locks
    def release_files(worktree:, file_paths:)
      count = session.file_locks.where(worktree: worktree, file_path: file_paths).delete_all
      { success: true, released: count }
    end

    # Check for conflicting locks
    def check_conflicts(worktree:, file_paths:)
      existing = session.file_locks
        .active
        .where(file_path: file_paths)
        .where.not(worktree: worktree)
        .includes(:worktree)

      existing.map do |lock|
        {
          file_path: lock.file_path,
          locked_by_worktree_id: lock.worktree_id,
          locked_by_branch: lock.worktree.branch_name,
          lock_type: lock.lock_type,
          acquired_at: lock.acquired_at&.iso8601
        }
      end
    end

    # Clean up expired locks
    def cleanup_expired
      count = session.file_locks.where("expires_at < ?", Time.current).delete_all
      { cleaned: count }
    end

    # Get all active locks for the session
    def active_locks
      session.file_locks.active.includes(:worktree).map { |l| lock_summary(l) }
    end

    private

    def lock_summary(lock)
      {
        id: lock.id,
        file_path: lock.file_path,
        worktree_id: lock.worktree_id,
        branch_name: lock.worktree&.branch_name,
        lock_type: lock.lock_type,
        acquired_at: lock.acquired_at&.iso8601,
        expires_at: lock.expires_at&.iso8601
      }
    end
  end
end
