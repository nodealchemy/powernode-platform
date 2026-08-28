# frozen_string_literal: true

module Ai
  class GoalPlan < ApplicationRecord
    self.table_name = "ai_goal_plans"

    STATUSES = %w[draft validated approved executing completed failed rejected].freeze

    # Statuses that mean the runner has already taken the plan. A plan in one
    # of these carries execution provenance on its steps
    # (metadata["last_outputs"] — the node_instance_ids verification, rollback
    # and adaptation read back), so nothing may rewrite or destroy its rows
    # behind the operator's back.
    EXECUTED_STATUSES = %w[executing completed failed].freeze

    belongs_to :account
    belongs_to :goal, class_name: "Ai::AgentGoal", foreign_key: "goal_id"
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id"
    belongs_to :approved_by, class_name: "User", foreign_key: "approved_by_id", optional: true

    has_many :steps, class_name: "Ai::GoalPlanStep", foreign_key: "plan_id", dependent: :destroy

    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :version, presence: true, uniqueness: { scope: :goal_id }

    attribute :plan_data, :json, default: -> { {} }
    attribute :validation_result, :json, default: -> { {} }
    attribute :risk_assessment, :json, default: -> { {} }

    scope :active, -> { where(status: %w[draft validated approved executing]) }
    scope :by_version, -> { order(version: :desc) }
    scope :for_goal, ->(goal_id) { where(goal_id: goal_id) }
    scope :approved, -> { where(status: "approved") }

    def approve!(user:)
      update!(
        status: "approved",
        approved_by: user,
        approved_at: Time.current
      )
    end

    def reject!(reason: nil)
      update!(
        status: "rejected",
        validation_result: validation_result.merge("rejection_reason" => reason)
      )
    end

    def start_execution!
      update!(status: "executing")
    end

    def complete!
      update!(status: "completed", completed_at: Time.current)
    end

    def fail!(reason: nil)
      update!(
        status: "failed",
        validation_result: validation_result.merge("failure_reason" => reason)
      )
    end

    def next_executable_step
      steps.where(status: "pending")
        .where.not("dependencies @> ?", [].to_json) # Has no unresolved dependencies
        .or(steps.where(status: "pending").where("dependencies = '[]'::jsonb"))
        .order(:step_number)
        .first
    end

    # True once the plan has left the review gate — either the plan itself is
    # in an executed status, or at least one step has moved off `pending`
    # (the runner claims a step before the plan status is stamped, so the
    # step check is not redundant). Callers that rewrite or delete steps —
    # the composer's collapse passes, the operator read path — use this to
    # stay off plans whose rows are the record of what actually ran.
    def execution_started?
      return true if EXECUTED_STATUSES.include?(status.to_s)

      steps.where.not(status: "pending").exists?
    end

    def all_steps_completed?
      steps.where.not(status: "completed").empty?
    end

    def progress_percentage
      return 0.0 if steps.empty?
      (steps.where(status: "completed").count.to_f / steps.count * 100).round(1)
    end
  end
end
