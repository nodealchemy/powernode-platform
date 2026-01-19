# frozen_string_literal: true

module Ai
  class TeamExecution < ApplicationRecord
    self.table_name = "ai_team_executions"

    STATUSES = %w[pending running paused completed failed cancelled timeout].freeze

    # Associations
    belongs_to :account
    belongs_to :agent_team, class_name: "AiAgentTeam"
    belongs_to :triggered_by, class_name: "User", optional: true

    has_many :tasks, class_name: "Ai::TeamTask", foreign_key: :team_execution_id, dependent: :destroy
    has_many :messages, class_name: "Ai::TeamMessage", foreign_key: :team_execution_id, dependent: :destroy

    # Validations
    validates :execution_id, presence: true, uniqueness: true
    validates :status, inclusion: { in: STATUSES }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :active, -> { where(status: %w[pending running paused]) }
    scope :recent, -> { order(created_at: :desc) }
    scope :for_account, ->(account_id) { where(account_id: account_id) }

    # Callbacks
    before_validation :generate_execution_id, on: :create

    # Status transitions
    def start!
      update!(status: "running", started_at: Time.current)
    end

    def pause!
      update!(status: "paused")
    end

    def resume!
      update!(status: "running")
    end

    def complete!(result = {})
      update!(
        status: "completed",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        output_result: result,
        termination_reason: "completed"
      )
    end

    def fail!(reason)
      update!(
        status: "failed",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        termination_reason: reason
      )
    end

    def cancel!(reason = "user_cancelled")
      update!(
        status: "cancelled",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        termination_reason: reason
      )
    end

    def timeout!
      update!(
        status: "timeout",
        completed_at: Time.current,
        duration_ms: calculate_duration,
        termination_reason: "timeout"
      )
    end

    # Status checks
    def active?
      %w[pending running paused].include?(status)
    end

    def finished?
      %w[completed failed cancelled timeout].include?(status)
    end

    # Task management
    def update_task_counts!
      update!(
        tasks_total: tasks.count,
        tasks_completed: tasks.where(status: "completed").count,
        tasks_failed: tasks.where(status: "failed").count
      )
    end

    def progress_percentage
      return 0 if tasks_total.zero?

      ((tasks_completed.to_f / tasks_total) * 100).round(2)
    end

    # Messaging
    def record_message!
      increment!(:messages_exchanged)
    end

    # Resource tracking
    def add_tokens!(count)
      increment!(:total_tokens_used, count)
    end

    def add_cost!(amount)
      update!(total_cost_usd: total_cost_usd + amount)
    end

    # Shared memory
    def get_memory(key)
      shared_memory[key]
    end

    def set_memory(key, value)
      update!(shared_memory: shared_memory.merge(key => value))
    end

    def clear_memory(key)
      new_memory = shared_memory.except(key)
      update!(shared_memory: new_memory)
    end

    private

    def generate_execution_id
      self.execution_id ||= "exec_#{SecureRandom.hex(12)}"
    end

    def calculate_duration
      return nil unless started_at.present?

      ((Time.current - started_at) * 1000).to_i
    end
  end
end
