# frozen_string_literal: true

module Ai
  # Audit row for one execution of a "recipe skill" by Ai::SkillRecipeRunner.
  # See migration 20260512010000_create_ai_skill_recipe_runs for column docs.
  class SkillRecipeRun < ApplicationRecord
    self.table_name = "ai_skill_recipe_runs"

    STATUSES = %w[pending running paused_for_approval completed failed cancelled].freeze
    TERMINAL_STATUSES = %w[completed failed cancelled].freeze

    belongs_to :account
    belongs_to :skill, class_name: "Ai::Skill", foreign_key: "ai_skill_id"
    belongs_to :user, optional: true
    belongs_to :agent, class_name: "Ai::Agent", foreign_key: "ai_agent_id", optional: true

    validates :status, inclusion: { in: STATUSES }

    scope :recent,                -> { order(created_at: :desc) }
    scope :paused_for_approval,   -> { where(status: "paused_for_approval") }
    scope :active,                -> { where(status: %w[pending running paused_for_approval]) }
    scope :terminal,              -> { where(status: TERMINAL_STATUSES) }
    scope :for_skill,             ->(skill_id) { where(ai_skill_id: skill_id) }

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def paused?
      status == "paused_for_approval"
    end

    def failed?
      status == "failed"
    end

    def successful?
      status == "completed"
    end

    def duration_ms
      return nil unless started_at && finished_at

      ((finished_at - started_at) * 1000).round
    end

    # Convenience for the runner: append a step result to the log.
    # Caller is responsible for save!.
    def append_step!(step_result)
      self.steps_log = (steps_log || []) + [step_result]
    end
  end
end
