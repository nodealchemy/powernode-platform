# frozen_string_literal: true

module Ai
  class MergeOperation < ApplicationRecord
    self.table_name = "ai_merge_operations"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[pending in_progress completed conflict failed rolled_back].freeze
    STRATEGIES = %w[merge rebase squash cherry_pick].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :worktree_session, class_name: "Ai::WorktreeSession"
    belongs_to :worktree, class_name: "Ai::Worktree"
    belongs_to :account

    # ==========================================
    # Validations
    # ==========================================
    validates :source_branch, presence: true
    validates :target_branch, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :strategy, inclusion: { in: STRATEGIES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :by_order, -> { order(:merge_order) }
    scope :pending_merges, -> { where(status: "pending") }
    scope :with_conflicts, -> { where(has_conflicts: true) }

    # ==========================================
    # State Machine
    # ==========================================
    def start!
      raise_invalid_transition!("start") unless status == "pending"

      update!(status: "in_progress", started_at: Time.current)
    end

    def complete!(merge_commit_sha:)
      raise_invalid_transition!("complete") unless status == "in_progress"

      now = Time.current
      update!(
        status: "completed",
        merge_commit_sha: merge_commit_sha,
        completed_at: now,
        duration_ms: started_at ? ((now - started_at) * 1000).to_i : nil
      )
    end

    def mark_conflict!(conflict_files: [], conflict_details: nil)
      update!(
        status: "conflict",
        has_conflicts: true,
        conflict_files: conflict_files,
        conflict_details: conflict_details,
        completed_at: Time.current
      )
    end

    def fail!(error_message: nil, error_code: nil)
      update!(
        status: "failed",
        error_message: error_message,
        error_code: error_code,
        completed_at: Time.current
      )
    end

    def rollback!(rollback_sha:)
      update!(
        status: "rolled_back",
        rollback_commit_sha: rollback_sha,
        rolled_back: true,
        rolled_back_at: Time.current
      )
    end

    # ==========================================
    # Helpers
    # ==========================================
    def conflicted?
      has_conflicts
    end

    def conflict_count
      conflict_files.size
    end

    def can_rollback?
      status == "completed" && merge_commit_sha.present?
    end

    def operation_summary
      {
        id: id,
        worktree_id: worktree_id,
        source_branch: source_branch,
        target_branch: target_branch,
        strategy: strategy,
        status: status,
        merge_order: merge_order,
        merge_commit_sha: merge_commit_sha,
        has_conflicts: has_conflicts,
        conflict_files: conflict_files,
        conflict_resolution: conflict_resolution,
        pull_request_url: pull_request_url,
        rolled_back: rolled_back,
        started_at: started_at&.iso8601,
        completed_at: completed_at&.iso8601,
        duration_ms: duration_ms
      }
    end

    private

    def raise_invalid_transition!(action)
      raise ActiveRecord::RecordInvalid.new(self),
        "Cannot #{action} merge operation in #{status} status"
    end
  end
end
