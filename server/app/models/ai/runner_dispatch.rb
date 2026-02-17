# frozen_string_literal: true

module Ai
  class RunnerDispatch < ApplicationRecord
    self.table_name = "ai_runner_dispatches"

    # ==========================================
    # Constants
    # ==========================================
    STATUSES = %w[pending dispatched running completed failed].freeze

    # ==========================================
    # Associations
    # ==========================================
    belongs_to :account
    belongs_to :worktree_session, class_name: "Ai::WorktreeSession", foreign_key: "worktree_session_id"
    belongs_to :worktree, class_name: "Ai::Worktree", foreign_key: "worktree_id"
    belongs_to :git_runner, class_name: "Devops::GitRunner", foreign_key: "git_runner_id", optional: true
    belongs_to :git_repository, class_name: "Devops::GitRepository", foreign_key: "git_repository_id", optional: true
    belongs_to :mission, class_name: "Ai::Mission", foreign_key: "mission_id", optional: true

    # ==========================================
    # Validations
    # ==========================================
    validates :status, inclusion: { in: STATUSES }

    # ==========================================
    # Scopes
    # ==========================================
    scope :pending, -> { where(status: "pending") }
    scope :dispatched, -> { where(status: "dispatched") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :active, -> { where(status: %w[pending dispatched running]) }
    scope :for_session, ->(session_id) { where(worktree_session_id: session_id) }
    scope :recent, -> { order(created_at: :desc) }

    # ==========================================
    # Helpers
    # ==========================================
    def dispatch_summary
      {
        id: id,
        account_id: account_id,
        worktree_session_id: worktree_session_id,
        worktree_id: worktree_id,
        git_runner_id: git_runner_id,
        git_repository_id: git_repository_id,
        workflow_run_id: workflow_run_id,
        workflow_url: workflow_url,
        status: status,
        input_params: input_params,
        output_result: output_result,
        runner_labels: runner_labels,
        dispatched_at: dispatched_at&.iso8601,
        completed_at: completed_at&.iso8601,
        duration_ms: duration_ms,
        created_at: created_at.iso8601
      }
    end
  end
end
