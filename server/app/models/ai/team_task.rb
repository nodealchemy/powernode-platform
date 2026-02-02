# frozen_string_literal: true

module Ai
  class TeamTask < ApplicationRecord
    self.table_name = "ai_team_tasks"

    STATUSES = %w[pending assigned in_progress waiting completed failed cancelled delegated].freeze
    TASK_TYPES = %w[execution review validation coordination escalation human_input].freeze

    # Associations
    belongs_to :team_execution, class_name: "Ai::TeamExecution"
    belongs_to :assigned_role, class_name: "Ai::TeamRole", optional: true
    belongs_to :assigned_agent, class_name: "AiAgent", optional: true
    belongs_to :parent_task, class_name: "Ai::TeamTask", optional: true
    belongs_to :delegated_from, class_name: "Ai::TeamTask", foreign_key: :delegated_from_task_id, optional: true

    has_many :subtasks, class_name: "Ai::TeamTask", foreign_key: :parent_task_id, dependent: :destroy
    has_many :delegated_tasks, class_name: "Ai::TeamTask", foreign_key: :delegated_from_task_id, dependent: :nullify

    # Delegate account access
    delegate :account, :agent_team, to: :team_execution

    # Validations
    validates :task_id, presence: true, uniqueness: true
    validates :description, presence: true
    validates :status, inclusion: { in: STATUSES }
    validates :task_type, inclusion: { in: TASK_TYPES }
    validates :priority, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 10 }, allow_nil: true
    validates :retry_count, numericality: { greater_than_or_equal_to: 0 }
    validates :max_retries, numericality: { greater_than_or_equal_to: 0 }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :in_progress, -> { where(status: "in_progress") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :active, -> { where(status: %w[pending assigned in_progress waiting]) }
    scope :root_tasks, -> { where(parent_task_id: nil) }
    scope :by_priority, -> { order(priority: :asc) }
    scope :for_role, ->(role_id) { where(assigned_role_id: role_id) }

    # Callbacks
    before_validation :generate_task_id, on: :create
    after_save :update_execution_counts, if: :saved_change_to_status?

    # Status transitions
    def assign!(role:, agent: nil)
      update!(
        status: "assigned",
        assigned_role: role,
        assigned_agent: agent,
        assigned_at: Time.current
      )
    end

    def start!
      update!(status: "in_progress", started_at: Time.current)
    end

    def wait!(reason = nil)
      update!(status: "waiting", metadata: metadata.merge("wait_reason" => reason))
    end

    def complete!(output = {})
      update!(
        status: "completed",
        output_data: output,
        completed_at: Time.current,
        duration_ms: calculate_duration
      )
    end

    def fail!(reason)
      if can_retry?
        increment!(:retry_count)
        update!(status: "pending", failure_reason: reason)
      else
        update!(
          status: "failed",
          failure_reason: reason,
          completed_at: Time.current,
          duration_ms: calculate_duration
        )
      end
    end

    def cancel!
      update!(
        status: "cancelled",
        completed_at: Time.current,
        duration_ms: calculate_duration
      )
    end

    def delegate!(to_role:, to_agent: nil)
      delegated = team_execution.tasks.create!(
        description: description,
        expected_output: expected_output,
        input_data: output_data.presence || input_data,
        task_type: task_type,
        priority: priority,
        assigned_role: to_role,
        assigned_agent: to_agent,
        delegated_from_task_id: id
      )

      update!(status: "delegated")
      delegated
    end

    # Status checks
    def active?
      %w[pending assigned in_progress waiting].include?(status)
    end

    def finished?
      %w[completed failed cancelled delegated].include?(status)
    end

    def can_retry?
      retry_count < max_retries
    end

    # Resource tracking
    def add_tokens!(count)
      increment!(:tokens_used, count)
      team_execution.add_tokens!(count)
    end

    def add_cost!(amount)
      update!(cost_usd: cost_usd + amount)
      team_execution.add_cost!(amount)
    end

    def record_tool_use!(tool_name)
      update!(tools_used: tools_used + [ tool_name ])
    end

    # Hierarchy
    def root_task
      parent_task&.root_task || self
    end

    def depth
      parent_task ? parent_task.depth + 1 : 0
    end

    private

    def generate_task_id
      self.task_id ||= "task_#{SecureRandom.hex(12)}"
    end

    def calculate_duration
      return nil unless started_at.present?

      ((Time.current - started_at) * 1000).to_i
    end

    def update_execution_counts
      team_execution.update_task_counts!
    end
  end
end
