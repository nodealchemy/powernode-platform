# frozen_string_literal: true

module Ai
  class WorkflowSchedule < ApplicationRecord
    include Schedulable

    # Associations
    belongs_to :workflow, class_name: "Ai::Workflow", foreign_key: "ai_workflow_id"
    belongs_to :created_by, class_name: "User"

    delegate :account, to: :workflow

    # Validations
    validates :name, presence: true, length: { maximum: 255 }
    validates :status, presence: true, inclusion: {
      in: %w[active paused disabled expired],
      message: "must be a valid schedule status"
    }
    validates :execution_count, numericality: { greater_than_or_equal_to: 0 }
    validate :validate_date_range_consistency
    validate :validate_max_executions

    # JSON columns
    attribute :input_variables, :json, default: -> { {} }
    attribute :configuration, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :active, -> { where(status: "active", is_active: true) }
    scope :inactive, -> { where.not(status: "active").or(where(is_active: false)) }
    scope :due_for_execution, -> {
      active.where("next_execution_at <= ?", Time.current)
            .where("starts_at IS NULL OR starts_at <= ?", Time.current)
            .where("ends_at IS NULL OR ends_at >= ?", Time.current)
    }
    scope :by_timezone, ->(tz) { where(timezone: tz) }

    # Callbacks
    before_validation :set_defaults, on: :create
    before_save :calculate_next_execution

    # Status check methods
    def active?
      status == "active" && is_active? && !expired?
    end

    def paused?
      status == "paused"
    end

    def disabled?
      status == "disabled" || !is_active?
    end

    def expired?
      status == "expired" ||
      (ends_at.present? && ends_at < Time.current) ||
      (max_executions.present? && execution_count >= max_executions)
    end

    def can_execute?
      active? && workflow.can_execute? && due_for_execution?
    end

    def due_for_execution?
      return false unless active?
      return false if next_execution_at.blank? || next_execution_at > Time.current
      return false if starts_at.present? && starts_at > Time.current
      return false if ends_at.present? && ends_at < Time.current
      return false if max_executions.present? && execution_count >= max_executions

      true
    end

    def execute_scheduled_workflow
      return false unless can_execute?

      begin
        workflow_run = workflow.execute(
          input_variables,
          user: created_by,
          trigger_type: "schedule"
        )

        increment!(:execution_count)
        update_columns(
          last_execution_at: Time.current,
          next_execution_at: calculate_next_execution_time
        )

        check_and_expire_if_needed

        workflow_run
      rescue StandardError => e
        handle_execution_error(e)
        raise
      end
    end

    def activate!
      return false unless %w[paused disabled].include?(status)

      update!(
        status: "active",
        is_active: true,
        next_execution_at: calculate_next_execution_time
      )
    end

    def pause!
      return false unless active?

      update!(status: "paused")
    end

    def disable!
      update!(
        status: "disabled",
        is_active: false
      )
    end

    def expire!
      update!(
        status: "expired",
        is_active: false,
        metadata: metadata.merge("expired_at" => Time.current.iso8601)
      )
    end

    def next_execution_time(from_time = Time.current)
      next_time = super(from_time)
      return nil if next_time.nil?
      return nil if ends_at.present? && next_time > ends_at

      next_time
    end

    def time_until_next_execution
      return nil if next_execution_at.blank?

      (next_execution_at - Time.current).to_i
    end

    def execution_summary
      {
        total_executions: execution_count,
        next_execution: next_execution_at,
        last_execution: last_execution_at,
        status: status,
        active: active?,
        expired: expired?
      }
    end

    def skip_if_running?
      configuration["skip_if_running"] || false
    end

    def should_notify_on_success?
      configuration.dig("notifications", "on_success") || false
    end

    def should_notify_on_failure?
      configuration.dig("notifications", "on_failure") || false
    end

    def human_readable_schedule
      cron_expression
    end

    private

    def set_defaults
      self.timezone ||= "UTC"
      self.is_active = true if is_active.nil?
      self.execution_count ||= 0

      if configuration.blank?
        self.configuration = {
          "skip_if_running" => true,
          "max_runtime_hours" => 24,
          "notifications" => {
            "on_success" => false,
            "on_failure" => true
          }
        }
      end
    end

    def calculate_next_execution
      return unless active? && cron_expression.present?

      self.next_execution_at = calculate_next_execution_time
    end

    def calculate_next_execution_time
      next_execution_time(last_execution_at || Time.current)
    end

    def validate_date_range_consistency
      return unless starts_at.present? && ends_at.present?

      if starts_at >= ends_at
        errors.add(:ends_at, "must be after starts_at")
      end
    end

    def validate_max_executions
      return unless max_executions.present?

      if max_executions <= 0
        errors.add(:max_executions, "must be greater than 0")
      end
    end

    def check_and_expire_if_needed
      should_expire = false

      if ends_at.present? && Time.current >= ends_at
        should_expire = true
      end

      if max_executions.present? && execution_count >= max_executions
        should_expire = true
      end

      expire! if should_expire
    end

    def handle_execution_error(error)
      Rails.logger.error "Scheduled workflow execution failed for schedule #{id}: #{error.message}"

      update!(
        metadata: metadata.merge({
          "last_error" => {
            "message" => error.message,
            "timestamp" => Time.current.iso8601,
            "error_count" => (metadata.dig("error_count") || 0) + 1
          }
        })
      )
    end
  end
end
