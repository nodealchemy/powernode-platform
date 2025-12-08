# frozen_string_literal: true

class AiWorkflowSchedule < ApplicationRecord
  # Authentication & Authorization
  belongs_to :ai_workflow
  belongs_to :created_by, class_name: 'User'

  # Associations
  delegate :account, to: :ai_workflow

  # Validations
  validates :name, presence: true, length: { maximum: 255 }
  validates :cron_expression, presence: true
  validates :timezone, presence: true
  validates :status, presence: true, inclusion: { 
    in: %w[active paused disabled expired],
    message: 'must be a valid schedule status'
  }
  validates :execution_count, numericality: { greater_than_or_equal_to: 0 }
  validate :validate_cron_expression
  validate :validate_date_range_consistency
  validate :validate_max_executions

  # JSON columns
  attribute :input_variables, :json, default: -> { {} }
  attribute :configuration, :json, default: -> { {} }
  attribute :metadata, :json, default: -> { {} }

  # Scopes
  scope :active, -> { where(status: 'active', is_active: true) }
  scope :inactive, -> { where.not(status: 'active').or(where(is_active: false)) }
  scope :due_for_execution, -> { 
    active.where('next_execution_at <= ?', Time.current)
          .where('starts_at IS NULL OR starts_at <= ?', Time.current)
          .where('ends_at IS NULL OR ends_at >= ?', Time.current)
  }
  scope :by_timezone, ->(tz) { where(timezone: tz) }
  scope :expiring_soon, ->(hours = 24) { 
    where('ends_at IS NOT NULL AND ends_at <= ?', hours.hours.from_now)
  }

  # Callbacks
  before_validation :set_defaults, on: :create
  before_save :calculate_next_execution
  after_create :log_schedule_created
  after_update :handle_status_changes, if: :saved_change_to_status?

  # Status check methods
  def active?
    status == 'active' && is_active? && !expired?
  end

  def paused?
    status == 'paused'
  end

  def disabled?
    status == 'disabled' || !is_active?
  end

  def expired?
    status == 'expired' || 
    (ends_at.present? && ends_at < Time.current) ||
    (max_executions.present? && execution_count >= max_executions)
  end

  # Execution management
  def can_execute?
    active? && ai_workflow.can_execute? && due_for_execution?
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
      # Execute the workflow
      workflow_run = ai_workflow.execute(
        input_variables,
        user: created_by,
        trigger_type: 'schedule'
      )

      # Update schedule tracking
      increment!(:execution_count)
      update_columns(
        last_execution_at: Time.current,
        next_execution_at: calculate_next_execution_time
      )

      # Check if schedule should be expired
      check_and_expire_if_needed

      # Log successful execution
      log_execution('scheduled_execution_triggered', "Workflow #{ai_workflow.name} executed on schedule", {
        'run_id' => workflow_run.run_id,
        'execution_count' => execution_count
      })

      workflow_run
    rescue StandardError => e
      handle_execution_error(e)
      raise
    end
  end

  # Schedule management
  def activate!
    return false unless %w[paused disabled].include?(status)

    update!(
      status: 'active',
      is_active: true,
      next_execution_at: calculate_next_execution_time
    )
  end

  def pause!
    return false unless active?

    update!(status: 'paused')
  end

  def disable!
    update!(
      status: 'disabled',
      is_active: false
    )
  end

  def expire!
    update!(
      status: 'expired',
      is_active: false,
      metadata: metadata.merge('expired_at' => Time.current.iso8601)
    )
  end

  # Cron and timing methods
  def next_execution_time(from_time = Time.current)
    return nil unless cron_expression.present?

    begin
      cron = Fugit::Cron.new(cron_expression)
      return nil unless cron

      # Convert from_time to the schedule's timezone for calculation
      tz = timezone.present? ? TZInfo::Timezone.get(timezone) : TZInfo::Timezone.get('UTC')
      from_time_in_tz = tz.to_local(from_time.utc)

      next_time = cron.next_time(from_time_in_tz)
      return nil unless next_time

      # Convert EtOrbi::EoTime to Time
      next_time = next_time.to_t if next_time.respond_to?(:to_t)

      # Apply date range constraints
      if ends_at.present? && next_time > ends_at
        return nil
      end

      next_time
    rescue StandardError => e
      Rails.logger.error "Failed to calculate next execution time for schedule #{id}: #{e.message}"
      nil
    end
  end

  def previous_execution_time(from_time = Time.current)
    return nil unless cron_expression.present?

    begin
      cron = Fugit::Cron.new(cron_expression)
      return nil unless cron

      prev_time = cron.previous_time(from_time)
      return nil unless prev_time

      # Convert EtOrbi::EoTime to Time
      prev_time.respond_to?(:to_t) ? prev_time.to_t : prev_time
    rescue StandardError => e
      Rails.logger.error "Failed to calculate previous execution time for schedule #{id}: #{e.message}"
      nil
    end
  end

  def execution_times_in_range(start_time, end_time)
    return [] unless cron_expression.present?

    times = []
    current_time = start_time
    
    while current_time < end_time
      next_time = next_execution_time(current_time)
      break unless next_time && next_time <= end_time
      
      times << next_time
      current_time = next_time + 1.minute
    end
    
    times
  end

  def time_until_next_execution
    return nil unless next_execution_at.present?
    
    [(next_execution_at - Time.current).to_i, 0].max
  end

  def human_readable_schedule
    return cron_expression unless cron_expression.present?

    begin
      cron = Fugit::Cron.new(cron_expression)
      # This would typically use a gem like chronic or a custom parser
      # For now, return the raw expression
      cron_expression
    rescue StandardError
      cron_expression
    end
  end

  # Schedule statistics
  def execution_summary
    {
      total_executions: execution_count,
      next_execution: next_execution_at,
      last_execution: last_execution_at,
      time_until_next: time_until_next_execution,
      is_due: due_for_execution?,
      status: status,
      active: active?,
      expired: expired?,
      remaining_executions: max_executions ? [max_executions - execution_count, 0].max : nil
    }
  end

  def recent_executions(limit = 10)
    ai_workflow.ai_workflow_runs
              .where(trigger_type: 'schedule')
              .where('created_at >= ?', 30.days.ago)
              .order(created_at: :desc)
              .limit(limit)
  end

  def success_rate(days = 30)
    runs = recent_executions(100).where('created_at >= ?', days.days.ago)
    return 0.0 if runs.empty?
    
    successful = runs.where(status: 'completed').count
    (successful.to_f / runs.count * 100).round(2)
  end

  # Configuration helpers
  def skip_if_running?
    configuration['skip_if_running'] != false
  end

  def notification_settings
    configuration['notifications'] || {}
  end

  def should_notify_on_success?
    notification_settings['on_success'] == true
  end

  def should_notify_on_failure?
    notification_settings['on_failure'] != false
  end

  private

  def set_defaults
    self.timezone ||= 'UTC'
    self.is_active = true if is_active.nil?
    self.execution_count ||= 0
    
    if configuration.blank?
      self.configuration = {
        'skip_if_running' => true,
        'max_runtime_hours' => 24,
        'notifications' => {
          'on_success' => false,
          'on_failure' => true
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

  def validate_cron_expression
    return unless cron_expression.present?

    begin
      Fugit::Cron.new(cron_expression)
    rescue StandardError => e
      errors.add(:cron_expression, "is invalid: #{e.message}")
    end
  end

  def validate_date_range_consistency
    return unless starts_at.present? && ends_at.present?

    if starts_at >= ends_at
      errors.add(:ends_at, 'must be after starts_at')
    end
  end

  def validate_max_executions
    return unless max_executions.present?

    if max_executions <= 0
      errors.add(:max_executions, 'must be greater than 0')
    end

    if max_executions.present? && execution_count >= max_executions
      errors.add(:max_executions, 'has already been reached')
    end
  end

  def handle_status_changes
    case status
    when 'active'
      self.next_execution_at = calculate_next_execution_time
    when 'paused', 'disabled', 'expired'
      self.next_execution_at = nil
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
    
    # Update metadata with error information
    update!(
      metadata: metadata.merge({
        'last_error' => {
          'message' => error.message,
          'timestamp' => Time.current.iso8601,
          'error_count' => (metadata.dig('error_count') || 0) + 1
        }
      })
    )

    # Log the error
    log_execution('scheduled_execution_failed', "Scheduled execution failed: #{error.message}", {
      'error_class' => error.class.name,
      'error_message' => error.message
    })
  end

  def log_schedule_created
    log_execution('schedule_created', "Workflow schedule created: #{name}", {
      'cron_expression' => cron_expression,
      'timezone' => timezone,
      'workflow_name' => ai_workflow.name
    })
  end

  def log_execution(event_type, message, context = {})
    # Create a log entry - this could be enhanced to use the workflow logging system
    Rails.logger.info "[Schedule #{id}] #{message}"
    
    # Update metadata with log entry
    log_entries = metadata['log_entries'] || []
    log_entries << {
      'event_type' => event_type,
      'message' => message,
      'context' => context,
      'timestamp' => Time.current.iso8601
    }
    
    # Keep only last 100 log entries
    log_entries = log_entries.last(100)
    
    update_column(:metadata, metadata.merge('log_entries' => log_entries))
  end
end