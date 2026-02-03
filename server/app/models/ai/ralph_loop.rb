# frozen_string_literal: true

module Ai
  class RalphLoop < ApplicationRecord
    # ==================== Concerns ====================
    include Auditable

    # ==================== Constants ====================
    STATUSES = %w[pending running paused completed failed cancelled].freeze
    TERMINAL_STATUSES = %w[completed failed cancelled].freeze
    AI_TOOLS = %w[amp claude_code ollama].freeze

    # Scheduling mode enumeration
    SCHEDULING_MODES = %w[manual scheduled continuous event_triggered].freeze

    # ==================== Associations ====================
    belongs_to :account
    belongs_to :container_instance, class_name: "Mcp::ContainerInstance", optional: true

    has_many :ralph_tasks, class_name: "Ai::RalphTask",
             foreign_key: "ralph_loop_id", dependent: :destroy
    has_many :ralph_iterations, class_name: "Ai::RalphIteration",
             foreign_key: "ralph_loop_id", dependent: :destroy

    # ==================== Validations ====================
    validates :name, presence: true, length: { maximum: 255 }
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :ai_tool, presence: true, inclusion: { in: AI_TOOLS }
    validates :scheduling_mode, inclusion: { in: SCHEDULING_MODES }
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
    scope :by_ai_tool, ->(tool) { where(ai_tool: tool) }
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
    before_save :calculate_duration, if: -> { completed_at_changed? && completed_at.present? }
    before_create :generate_webhook_token, if: -> { scheduling_mode == "event_triggered" }
    after_save :update_task_counts, if: :saved_change_to_status?
    after_save :broadcast_status_update, if: :saved_change_to_status?
    after_save :update_next_scheduled_at, if: :saved_change_to_scheduling_mode?

    # ==================== State Machine Methods ====================

    def start!
      raise InvalidTransitionError, "Cannot start loop in #{status} status" unless can_start?

      update!(
        status: "running",
        started_at: Time.current
      )
    end

    def pause!
      raise InvalidTransitionError, "Cannot pause loop in #{status} status" unless can_pause?

      update!(status: "paused")
    end

    def resume!
      raise InvalidTransitionError, "Cannot resume loop in #{status} status" unless can_resume?

      update!(status: "running")
    end

    def complete!(result: {})
      raise InvalidTransitionError, "Cannot complete loop in #{status} status" unless can_complete?

      update!(
        status: "completed",
        completed_at: Time.current,
        configuration: configuration.merge("final_result" => result)
      )
    end

    def fail!(error_message:, error_code: nil, error_details: {})
      raise InvalidTransitionError, "Cannot fail loop in #{status} status" unless can_fail?

      update!(
        status: "failed",
        completed_at: Time.current,
        error_message: error_message,
        error_code: error_code,
        error_details: error_details
      )
    end

    def cancel!(reason: nil)
      raise InvalidTransitionError, "Cannot cancel loop in #{status} status" unless can_cancel?

      update!(
        status: "cancelled",
        completed_at: Time.current,
        configuration: configuration.merge("cancellation_reason" => reason)
      )
    end

    def reset!
      raise InvalidTransitionError, "Cannot reset loop in #{status} status" unless can_reset?

      transaction do
        # Reset loop state
        update!(
          status: "pending",
          current_iteration: 0,
          started_at: nil,
          completed_at: nil,
          error_message: nil,
          error_code: nil,
          error_details: {}
        )

        # Reset all tasks to pending (except those that were skipped intentionally)
        ralph_tasks.where.not(status: "skipped").update_all(
          status: "pending",
          error_message: nil,
          error_code: nil,
          execution_attempts: 0,
          completed_in_iteration: nil,
          iteration_completed_at: nil
        )
      end
    end

    # ==================== State Checks ====================

    def can_start?
      status == "pending"
    end

    def can_reset?
      terminal?
    end

    def can_pause?
      status == "running"
    end

    def can_resume?
      status == "paused"
    end

    def can_complete?
      status.in?(%w[running paused])
    end

    def can_fail?
      status.in?(%w[pending running paused])
    end

    def can_cancel?
      !terminal?
    end

    def terminal?
      TERMINAL_STATUSES.include?(status)
    end

    def in_progress?
      !terminal?
    end

    def running?
      status == "running"
    end

    def max_iterations_reached?
      current_iteration >= max_iterations
    end

    # ==================== Scheduling Methods ====================

    # Calculate next execution time based on scheduling mode
    def calculate_next_scheduled_at
      case scheduling_mode
      when "scheduled"
        parse_cron_next_occurrence
      when "continuous"
        Time.current + (schedule_config["iteration_interval_seconds"] || 300).seconds
      else
        nil
      end
    end

    # Schedule the next iteration
    def schedule_next_iteration!
      return unless scheduling_mode.in?(%w[scheduled continuous])
      return if schedule_paused?
      return if exceeded_daily_limit?

      update!(
        next_scheduled_at: calculate_next_scheduled_at,
        last_scheduled_at: Time.current
      )
    end

    # Pause the schedule
    def pause_schedule!(reason: nil)
      update!(
        schedule_paused: true,
        schedule_paused_at: Time.current,
        schedule_paused_reason: reason
      )
    end

    # Resume the schedule
    def resume_schedule!
      update!(
        schedule_paused: false,
        schedule_paused_at: nil,
        schedule_paused_reason: nil,
        next_scheduled_at: calculate_next_scheduled_at
      )
    end

    # Check if daily iteration limit exceeded
    def exceeded_daily_limit?
      max_per_day = schedule_config["max_iterations_per_day"]
      return false if max_per_day.blank?

      reset_daily_counter_if_needed
      daily_iteration_count >= max_per_day
    end

    # Increment daily iteration count
    def increment_daily_iteration_count!
      reset_daily_counter_if_needed
      increment!(:daily_iteration_count)
    end

    # Check if loop is schedulable
    def schedulable?
      scheduling_mode.in?(%w[scheduled continuous event_triggered])
    end

    # Check if within schedule date range
    def within_schedule_range?
      start_at = schedule_config["start_at"]&.to_datetime
      end_at = schedule_config["end_at"]&.to_datetime
      now = Time.current

      (start_at.nil? || now >= start_at) && (end_at.nil? || now <= end_at)
    end

    # Check if should skip when already running
    def should_skip_if_running?
      schedule_config["skip_if_running"] != false && status == "running"
    end

    # Regenerate webhook token
    def regenerate_webhook_token!
      token = SecureRandom.urlsafe_base64(32)
      update!(webhook_token: token)
      token
    end

    # ==================== Task Management ====================

    def next_task
      ralph_tasks.pending.order(priority: :desc, position: :asc).find(&:dependencies_satisfied?)
    end

    def blocked_tasks
      ralph_tasks.where(status: "blocked")
    end

    def all_tasks_completed?
      ralph_tasks.where.not(status: %w[passed skipped]).empty?
    end

    def progress_percentage
      return 0 if total_tasks.zero?

      (completed_tasks.to_f / total_tasks * 100).round(1)
    end

    # ==================== Learning Management ====================

    def add_learning(learning_text, context: {})
      learning_entry = {
        "text" => learning_text,
        "iteration" => current_iteration,
        "timestamp" => Time.current.iso8601,
        "context" => context
      }

      self.learnings = (learnings || []) + [ learning_entry ]
      save!
    end

    def recent_learnings(limit: 10)
      (learnings || []).last(limit)
    end

    # ==================== Iteration Management ====================

    def increment_iteration!
      update!(current_iteration: current_iteration + 1)
    end

    def create_iteration(task: nil)
      ralph_iterations.create!(
        ralph_task: task,
        iteration_number: current_iteration + 1,
        status: "pending"
      )
    end

    # ==================== Summary Methods ====================

    def loop_summary
      {
        id: id,
        name: name,
        status: status,
        ai_tool: ai_tool,
        current_iteration: current_iteration,
        max_iterations: max_iterations,
        total_tasks: total_tasks,
        completed_tasks: completed_tasks,
        failed_tasks: failed_tasks,
        # Frontend expects task_count and completed_task_count
        task_count: total_tasks,
        completed_task_count: completed_tasks,
        progress_percentage: progress_percentage,
        started_at: started_at&.iso8601,
        completed_at: completed_at&.iso8601,
        duration_ms: duration_ms,
        created_at: created_at.iso8601,
        # Scheduling fields
        scheduling_mode: scheduling_mode,
        schedule_paused: schedule_paused,
        next_scheduled_at: next_scheduled_at&.iso8601,
        last_scheduled_at: last_scheduled_at&.iso8601,
        daily_iteration_count: daily_iteration_count
      }
    end

    def loop_details
      loop_summary.merge(
        description: description,
        repository_url: repository_url,
        branch: branch,
        progress_text: progress_text,
        learnings: learnings,
        configuration: configuration,
        prd_json: prd_json,
        error_message: error_message,
        error_code: error_code,
        tasks: ralph_tasks.ordered.map(&:task_summary),
        recent_iterations: ralph_iterations.order(iteration_number: :desc).limit(10).map(&:iteration_summary),
        # Scheduling details
        schedule_config: schedule_config,
        schedule_paused_at: schedule_paused_at&.iso8601,
        schedule_paused_reason: schedule_paused_reason,
        webhook_token: webhook_token,
        daily_iteration_reset_at: daily_iteration_reset_at&.iso8601
      )
    end

    # ==================== Custom Errors ====================

    class InvalidTransitionError < StandardError; end

    private

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

    # Parse cron expression and get next occurrence
    def parse_cron_next_occurrence
      cron_expr = schedule_config["cron_expression"]
      return nil if cron_expr.blank?

      begin
        cron = Fugit::Cron.parse(cron_expr)
        return nil unless cron

        timezone = schedule_config["timezone"] || "UTC"
        cron.next_time(Time.current.in_time_zone(timezone)).to_time
      rescue StandardError => e
        Rails.logger.error("Failed to parse cron expression '#{cron_expr}': #{e.message}")
        nil
      end
    end

    # Reset daily counter if it's a new day
    def reset_daily_counter_if_needed
      return if daily_iteration_reset_at == Date.current

      update_columns(
        daily_iteration_count: 0,
        daily_iteration_reset_at: Date.current
      )
    end

    # Generate webhook token for event-triggered mode
    def generate_webhook_token
      return if webhook_token.present?

      self.webhook_token = SecureRandom.urlsafe_base64(32)
    end

    # Update next scheduled time when scheduling mode changes
    def update_next_scheduled_at
      if scheduling_mode.in?(%w[scheduled continuous])
        update_columns(next_scheduled_at: calculate_next_scheduled_at)
      else
        update_columns(next_scheduled_at: nil)
      end
    end

    # Validate schedule configuration
    def validate_schedule_config
      case scheduling_mode
      when "scheduled"
        if schedule_config["cron_expression"].blank?
          errors.add(:schedule_config, "must include cron_expression for scheduled mode")
        else
          begin
            cron = Fugit::Cron.parse(schedule_config["cron_expression"])
            errors.add(:schedule_config, "has invalid cron_expression") unless cron
          rescue StandardError
            errors.add(:schedule_config, "has invalid cron_expression")
          end
        end
      when "continuous"
        interval = schedule_config["iteration_interval_seconds"]
        if interval.blank? || interval.to_i < 60
          errors.add(:schedule_config, "must include iteration_interval_seconds (min 60) for continuous mode")
        end
      end
    end
  end
end
