# frozen_string_literal: true

module Ai
  class RalphLoop < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable
    include Ai::RalphLoopConcerns::StateMachine
    include Ai::RalphLoopConcerns::Scheduling
    include Ai::RalphLoopConcerns::TaskAndLearning

    # ==================== Constants ====================
    STATUSES = %w[pending running paused completed failed cancelled].freeze
    TERMINAL_STATUSES = %w[completed failed cancelled].freeze

    # Scheduling mode enumeration
    SCHEDULING_MODES = %w[manual scheduled continuous event_triggered].freeze

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :default_agent, class_name: "Ai::Agent", foreign_key: "default_agent_id", optional: true
    belongs_to :container_instance, class_name: "Devops::ContainerInstance", foreign_key: "container_instance_id", optional: true
    belongs_to :risk_contract, class_name: "Ai::CodeFactory::RiskContract",
               foreign_key: "risk_contract_id", optional: true
    belongs_to :mission, class_name: "Ai::Mission", foreign_key: "mission_id", optional: true

    has_many :ralph_tasks, class_name: "Ai::RalphTask",
             foreign_key: "ralph_loop_id", dependent: :destroy
    has_many :ralph_iterations, class_name: "Ai::RalphIteration",
             foreign_key: "ralph_loop_id", dependent: :destroy

    # ==================== Validations ====================
    validates :name, presence: true, length: { maximum: 255 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :default_agent, presence: true, on: :start
    validates :scheduling_mode, inclusion: { in: SCHEDULING_MODES }
    validate :default_agent_belongs_to_account, if: :default_agent_id_changed?
    validates :current_iteration, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :max_iterations, numericality: { only_integer: true, greater_than: 0 }
    validates :repository_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https git ssh]),
                                         allow_blank: true }
    validates :webhook_token, uniqueness: true, allow_nil: true
    validate :validate_schedule_config, if: -> { scheduling_mode != "manual" }

    # ==================== Scopes ====================
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :paused, -> { where(status: "paused") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :terminal, -> { where(status: TERMINAL_STATUSES) }
    scope :active, -> { where(status: %w[pending running paused]) }
    scope :recent, -> { order(created_at: :desc) }

    # Scheduling scopes
    scope :scheduled, -> { where(scheduling_mode: %w[scheduled continuous]) }
    scope :event_triggered, -> { where(scheduling_mode: "event_triggered") }
    scope :due_for_execution, -> {
      where(schedule_paused: false)
        .where("next_scheduled_at <= ?", Time.current)
        .where(status: %w[pending running paused])
    }

    # ==================== Callbacks ====================
    before_validation :set_defaults, on: :create
    before_save :calculate_duration, if: -> { completed_at_changed? && completed_at.present? }
    before_create :generate_webhook_token, if: -> { scheduling_mode == "event_triggered" }
    after_save :update_task_counts, if: :saved_change_to_status?
    after_save :broadcast_status_update, if: :saved_change_to_status?
    after_save :update_next_scheduled_at, if: :saved_change_to_scheduling_mode?

    # ==================== Custom Errors ====================

    class InvalidTransitionError < StandardError; end

    def code_factory_mode?
      code_factory_mode == true
    end

    private

    def set_defaults
      self.status ||= "pending"
      self.scheduling_mode ||= "manual"
      self.configuration ||= {}
      self.prd_json ||= {}
      self.learnings ||= []
      self.current_iteration ||= 0
      self.max_iterations ||= 10
      self.total_tasks ||= 0
      self.completed_tasks ||= 0
      self.failed_tasks ||= 0
      self.code_factory_mode ||= false
    end

    def default_agent_belongs_to_account
      return unless default_agent && default_agent.account_id != account_id

      errors.add(:default_agent, "must belong to the same account")
    end

    def calculate_duration
      return unless started_at.present? && completed_at.present?

      self.duration_ms = ((completed_at - started_at) * 1000).to_i
    end

    def update_task_counts
      # Use update_columns to persist without triggering callbacks
      update_columns(
        total_tasks: ralph_tasks.count,
        completed_tasks: ralph_tasks.where(status: "passed").count,
        failed_tasks: ralph_tasks.where(status: "failed").count
      )
    end

    def broadcast_status_update
      # Use AiOrchestrationChannel for consistent real-time updates
      event_type = case status
      when "running" then saved_change_to_status? && status_before_last_save == "pending" ? "started" : "progress"
      when "completed" then "completed"
      when "failed" then "failed"
      when "paused" then "paused"
      when "cancelled" then "cancelled"
      else "progress"
      end

      AiOrchestrationChannel.broadcast_ralph_loop_event(self, event_type)
    rescue StandardError => e
      Rails.logger.warn("Failed to broadcast Ralph loop update: #{e.message}")
    end
  end
end
