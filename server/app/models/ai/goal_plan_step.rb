# frozen_string_literal: true

module Ai
  class GoalPlanStep < ApplicationRecord
    self.table_name = "ai_goal_plan_steps"

    STATUSES = %w[pending executing completed failed skipped].freeze
    STEP_TYPES = %w[agent_execution workflow_run observation human_review sub_goal].freeze

    belongs_to :plan, class_name: "Ai::GoalPlan", foreign_key: "plan_id"
    belongs_to :sub_goal, class_name: "Ai::AgentGoal", foreign_key: "sub_goal_id", optional: true
    belongs_to :ralph_task, class_name: "Ai::RalphTask", foreign_key: "ralph_task_id", optional: true

    validates :step_number, presence: true, uniqueness: { scope: :plan_id }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :step_type, presence: true, inclusion: { in: STEP_TYPES }

    attribute :dependencies, :json, default: -> { [] }
    attribute :execution_config, :json, default: -> { {} }

    scope :pending, -> { where(status: "pending") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :in_order, -> { order(:step_number) }

    def start!
      update!(status: "executing", started_at: Time.current)
    end

    def complete!(result: nil)
      update!(status: "completed", result_summary: result, completed_at: Time.current)
    end

    def fail!(reason: nil)
      update!(status: "failed", result_summary: reason, completed_at: Time.current)
    end

    def dependencies_met?
      return true if dependencies.blank?

      dep_step_numbers = dependencies.map(&:to_i)
      plan.steps.where(step_number: dep_step_numbers, status: "completed").count == dep_step_numbers.size
    end
  end
end
