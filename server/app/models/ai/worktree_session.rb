# frozen_string_literal: true

module Ai
  class WorktreeSession < ApplicationRecord
    self.table_name = "ai_worktree_sessions"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[pending provisioning active merging completed failed cancelled].freeze
    MERGE_STRATEGIES = %w[sequential integration_branch manual].freeze
    TERMINAL_STATUSES = %w[completed failed cancelled].freeze
    EXECUTION_MODES = %w[complementary competitive].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :initiated_by, class_name: "User", optional: true
    belongs_to :source, polymorphic: true, optional: true
    has_many :worktrees, class_name: "Ai::Worktree", foreign_key: "worktree_session_id", dependent: :destroy
    has_many :merge_operations, class_name: "Ai::MergeOperation", foreign_key: "worktree_session_id", dependent: :destroy
    has_many :file_locks, class_name: "Ai::FileLock", foreign_key: "worktree_session_id", dependent: :destroy

    # ==========================================
    # Validations
    # ==========================================
    validates :repository_path, presence: true
    validates :base_branch, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :merge_strategy, inclusion: { in: MERGE_STRATEGIES }
    validates :max_parallel, numericality: { greater_than: 0, less_than_or_equal_to: 20 }
    validates :execution_mode, inclusion: { in: EXECUTION_MODES }
    validates :max_duration_seconds, numericality: { greater_than: 0 }, allow_nil: true

    # ==========================================
    # Scopes
    # ==========================================
    scope :active_sessions, -> { where(status: %w[pending provisioning active merging]) }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_source, ->(source) { where(source: source) }

    # ==========================================
    # Callbacks
    # ==========================================
    after_save :broadcast_status_update, if: :saved_change_to_status?

    # ==========================================
    # State Machine
    # ==========================================
    def start!
      raise_invalid_transition!("start", status) unless status == "pending"

      update!(status: "provisioning", started_at: Time.current)
    end

    def activate!
      raise_invalid_transition!("activate", status) unless status == "provisioning"

      update!(status: "active")
    end

    def begin_merge!
      raise_invalid_transition!("begin_merge", status) unless status == "active"

      update!(status: "merging")
    end

    def complete!
      raise_invalid_transition!("complete", status) unless status.in?(%w[merging active])

      now = Time.current
      update!(
        status: "completed",
        completed_at: now,
        duration_ms: started_at ? ((now - started_at) * 1000).to_i : nil
      )
    end

    def fail!(error_message: nil, error_code: nil, error_details: {})
      now = Time.current
      update!(
        status: "failed",
        completed_at: now,
        duration_ms: started_at ? ((now - started_at) * 1000).to_i : nil,
        error_message: error_message,
        error_code: error_code,
        error_details: error_details
      )
    end

    def cancel!
      raise_invalid_transition!("cancel", status) if terminal?

      now = Time.current
      update!(
        status: "cancelled",
        completed_at: now,
        duration_ms: started_at ? ((now - started_at) * 1000).to_i : nil
      )
    end

    # ==========================================
    # Helpers
    # ==========================================
    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def progress_percentage
      return 0 if total_worktrees.zero?

      ((completed_worktrees.to_f / total_worktrees) * 100).round(1)
    end

    def all_worktrees_completed?
      total_worktrees.positive? && (completed_worktrees + failed_worktrees) >= total_worktrees
    end

    def failure_policy
      configuration.dig("failure_policy") || "continue"
    end

    def competitive?
      execution_mode == "competitive"
    end

    def require_tests?
      configuration.dig("require_tests") == true
    end

    def update_conflict_matrix!(matrix)
      update!(conflict_matrix: matrix)
    end

    def session_summary
      {
        id: id,
        status: status,
        repository_path: repository_path,
        base_branch: base_branch,
        merge_strategy: merge_strategy,
        max_parallel: max_parallel,
        total_worktrees: total_worktrees,
        completed_worktrees: completed_worktrees,
        failed_worktrees: failed_worktrees,
        progress_percentage: progress_percentage,
        source_type: source_type,
        source_id: source_id,
        execution_mode: execution_mode,
        max_duration_seconds: max_duration_seconds,
        conflict_matrix: conflict_matrix,
        error_message: error_message,
        started_at: started_at&.iso8601,
        completed_at: completed_at&.iso8601,
        duration_ms: duration_ms,
        created_at: created_at.iso8601
      }
    end

    private

    def raise_invalid_transition!(action, current)
      raise ActiveRecord::RecordInvalid.new(self),
        "Cannot #{action} session in #{current} status"
    end

    def broadcast_status_update
      AiOrchestrationChannel.broadcast_worktree_session_event(self, "status_changed", {
        previous_status: status_before_last_save,
        new_status: status
      })
    rescue StandardError => e
      Rails.logger.warn "[WorktreeSession] Broadcast failed: #{e.message}"
    end
  end
end
