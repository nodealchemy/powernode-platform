# frozen_string_literal: true

module Ai
  class Worktree < ApplicationRecord
    self.table_name = "ai_worktrees"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[pending creating ready in_use testing completed merged cleaned_up failed].freeze
    TEST_STATUSES = %w[pending running passed failed skipped].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :worktree_session, class_name: "Ai::WorktreeSession", foreign_key: "worktree_session_id"
    belongs_to :account
    belongs_to :ai_agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true
    belongs_to :assignee, polymorphic: true, optional: true
    has_many :merge_operations, class_name: "Ai::MergeOperation", foreign_key: "worktree_id", dependent: :destroy
    has_many :file_locks, class_name: "Ai::FileLock", foreign_key: "worktree_id", dependent: :destroy
    has_one :runner_dispatch, class_name: "Ai::RunnerDispatch", foreign_key: "worktree_id"

    # ==========================================
    # Validations
    # ==========================================
    validates :branch_name, presence: true, uniqueness: true
    validates :worktree_path, presence: true, uniqueness: true
    validates :status, inclusion: { in: STATUSES }
    validates :test_status, inclusion: { in: TEST_STATUSES }, allow_nil: true

    # ==========================================
    # Scopes
    # ==========================================
    scope :active, -> { where(status: %w[pending creating ready in_use testing]) }
    scope :completed_or_merged, -> { where(status: %w[completed merged]) }
    scope :by_session, ->(session_id) { where(worktree_session_id: session_id) }

    # ==========================================
    # Callbacks
    # ==========================================
    after_save :update_session_counts, if: :saved_change_to_status?
    after_save :broadcast_status_update, if: :saved_change_to_status?

    # ==========================================
    # State Machine
    # ==========================================
    def mark_creating!
      raise_invalid_transition!("mark_creating") unless status == "pending"

      update!(status: "creating")
    end

    def mark_ready!
      raise_invalid_transition!("mark_ready") unless status == "creating"

      update!(status: "ready", ready_at: Time.current)
    end

    def mark_in_use!
      raise_invalid_transition!("mark_in_use") unless status == "ready"

      update!(status: "in_use")
    end

    def complete!(head_sha: nil, stats: {})
      raise_invalid_transition!("complete") unless status.in?(%w[in_use testing])

      now = Time.current
      update!(
        status: "completed",
        completed_at: now,
        duration_ms: ready_at ? ((now - ready_at) * 1000).to_i : nil,
        head_commit_sha: head_sha || head_commit_sha,
        files_changed: stats[:files_changed] || files_changed,
        lines_added: stats[:lines_added] || lines_added,
        lines_removed: stats[:lines_removed] || lines_removed
      )
    end

    def fail!(error_message: nil, error_code: nil)
      update!(
        status: "failed",
        completed_at: Time.current,
        error_message: error_message,
        error_code: error_code
      )
    end

    def mark_merged!
      raise_invalid_transition!("mark_merged") unless status == "completed"

      update!(status: "merged")
    end

    def mark_cleaned_up!
      update!(status: "cleaned_up")
    end

    # ==========================================
    # Lock Management
    # ==========================================
    def lock!(reason:)
      update!(locked: true, lock_reason: reason, locked_at: Time.current)
    end

    def unlock!
      update!(locked: false, lock_reason: nil, locked_at: nil)
    end

    # ==========================================
    # Container Integration
    # ==========================================
    def container_instance_id
      metadata&.dig("container_instance_id")
    end

    def container_template_id
      metadata&.dig("container_template_id")
    end

    def track_container_instance!(instance_id)
      update!(metadata: (metadata || {}).merge("container_instance_id" => instance_id))
    end

    def mark_testing!
      raise_invalid_transition!("mark_testing") unless status == "in_use"

      update!(status: "testing", test_status: "pending")
    end

    def mark_test_passed!
      update!(test_status: "passed")
      complete! if status == "testing"
    end

    def mark_test_failed!(error: nil)
      update!(test_status: "failed")
      fail!(error_message: error || "Tests failed") if status == "testing"
    end

    # ==========================================
    # Helpers
    # ==========================================
    def agent_name
      ai_agent&.name
    end

    def worktree_summary
      {
        id: id,
        worktree_session_id: worktree_session_id,
        branch_name: branch_name,
        worktree_path: worktree_path,
        status: status,
        ai_agent_id: ai_agent_id,
        agent_name: agent_name,
        base_commit_sha: base_commit_sha,
        head_commit_sha: head_commit_sha,
        commit_count: commit_count,
        locked: locked,
        healthy: healthy,
        files_changed: files_changed,
        lines_added: lines_added,
        lines_removed: lines_removed,
        ready_at: ready_at&.iso8601,
        completed_at: completed_at&.iso8601,
        duration_ms: duration_ms,
        tokens_used: tokens_used,
        estimated_cost_cents: estimated_cost_cents,
        timeout_at: timeout_at&.iso8601,
        test_status: test_status,
        error_message: error_message,
        container_instance_id: container_instance_id,
        container_template_id: container_template_id,
        created_at: created_at.iso8601
      }
    end

    # ==========================================
    # Cost Tracking
    # ==========================================
    def update_cost!(tokens:, cost_cents:)
      update!(
        tokens_used: (tokens_used || 0) + tokens,
        estimated_cost_cents: (estimated_cost_cents || 0) + cost_cents
      )
    end

    def timed_out?
      timeout_at.present? && Time.current > timeout_at
    end

    private

    def raise_invalid_transition!(action)
      raise ActiveRecord::RecordInvalid.new(self),
        "Cannot #{action} worktree in #{status} status"
    end

    def update_session_counts
      session = worktree_session
      return unless session

      completed = session.worktrees.where(status: %w[completed merged cleaned_up]).count
      failed = session.worktrees.where(status: "failed").count

      session.update_columns(
        completed_worktrees: completed,
        failed_worktrees: failed
      )
    end

    def broadcast_status_update
      AiOrchestrationChannel.broadcast_worktree_event(self, "status_changed", {
        previous_status: status_before_last_save,
        new_status: status
      })
    rescue StandardError => e
      Rails.logger.warn "[Worktree] Broadcast failed: #{e.message}"
    end
  end
end
