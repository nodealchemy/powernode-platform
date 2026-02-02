# frozen_string_literal: true

# Schedulable concern for models that need cron-based scheduling
# Provides common scheduling behavior including cron validation, next/previous execution time,
# and timezone handling using the Fugit gem.
#
# Required columns:
#   - cron_expression (string, required)
#   - timezone (string, default: 'UTC')
#   - next_run_at or next_execution_at (datetime)
#   - last_run_at or last_execution_at (datetime, optional)
#   - is_active (boolean)
#
# Example usage:
#   class MySchedule < ApplicationRecord
#     include Schedulable
#   end
#
module Schedulable
  extend ActiveSupport::Concern

  included do
    # Validations
    validates :cron_expression, presence: true
    validates :timezone, presence: true
    validate :validate_cron_expression

    # Scopes
    scope :active_schedules, -> { where(is_active: true) }
    scope :inactive_schedules, -> { where(is_active: false) }
    scope :by_timezone, ->(tz) { where(timezone: tz) }

    # Callbacks
    before_save :recalculate_next_run, if: :should_recalculate_next_run?
  end

  # Calculate the next execution time from a given starting point
  #
  # @param from_time [Time] Starting point (default: Time.current)
  # @return [Time, nil] Next execution time or nil if invalid/inactive
  def next_execution_time(from_time = Time.current)
    return nil unless cron_expression.present?

    cron = parse_cron_expression
    return nil unless cron

    Time.use_zone(schedule_timezone) do
      next_time = cron.next_time(from_time)
      return nil unless next_time

      next_time.respond_to?(:to_t) ? next_time.to_t : next_time
    end
  rescue StandardError => e
    Rails.logger.error "[Schedulable] Failed to calculate next execution time: #{e.message}"
    nil
  end

  # Calculate the previous execution time from a given starting point
  #
  # @param from_time [Time] Starting point (default: Time.current)
  # @return [Time, nil] Previous execution time or nil if invalid
  def previous_execution_time(from_time = Time.current)
    return nil unless cron_expression.present?

    cron = parse_cron_expression
    return nil unless cron

    prev_time = cron.previous_time(from_time)
    return nil unless prev_time

    prev_time.respond_to?(:to_t) ? prev_time.to_t : prev_time
  rescue StandardError => e
    Rails.logger.error "[Schedulable] Failed to calculate previous execution time: #{e.message}"
    nil
  end

  # Get all execution times within a date range
  #
  # @param start_time [Time] Range start
  # @param end_time [Time] Range end
  # @param max_count [Integer] Maximum number of times to return (default: 100)
  # @return [Array<Time>] Execution times in range
  def execution_times_in_range(start_time, end_time, max_count: 100)
    return [] unless cron_expression.present?

    times = []
    current_time = start_time

    while current_time < end_time && times.length < max_count
      next_time = next_execution_time(current_time)
      break unless next_time && next_time <= end_time

      times << next_time
      current_time = next_time + 1.minute
    end

    times
  end

  # Check if schedule is due for execution
  #
  # @return [Boolean]
  def due?
    schedule_active? && next_run_timestamp.present? && next_run_timestamp <= Time.current
  end

  # Time until next execution in seconds
  #
  # @return [Integer, nil] Seconds until next run or nil if no next run
  def time_until_next_run
    timestamp = next_run_timestamp
    return nil unless timestamp.present?

    [ (timestamp - Time.current).to_i, 0 ].max
  end

  # Human-readable cron description
  #
  # @return [String] Description or raw expression
  def cron_description
    Shared::CronDescriptor.describe(cron_expression)
  rescue StandardError
    cron_expression
  end

  # Parse the cron expression
  #
  # @return [Fugit::Cron, nil]
  def parse_cron_expression
    return nil unless cron_expression.present?

    Fugit::Cron.parse(cron_expression) || Fugit::Cron.new(cron_expression)
  rescue StandardError
    nil
  end

  private

  # Get the schedule's timezone, defaulting to UTC
  def schedule_timezone
    timezone.presence || "UTC"
  end

  # Check if schedule is active (handles both is_active and status patterns)
  def schedule_active?
    if respond_to?(:status)
      is_active? && status == "active"
    else
      is_active?
    end
  end

  # Get the next run timestamp (handles different column names)
  def next_run_timestamp
    if respond_to?(:next_execution_at)
      next_execution_at
    elsif respond_to?(:next_run_at)
      next_run_at
    end
  end

  # Set the next run timestamp (handles different column names)
  def set_next_run_timestamp(value)
    if respond_to?(:next_execution_at=)
      self.next_execution_at = value
    elsif respond_to?(:next_run_at=)
      self.next_run_at = value
    end
  end

  # Get the last run timestamp for calculation reference
  def last_run_timestamp
    if respond_to?(:last_execution_at)
      last_execution_at
    elsif respond_to?(:last_run_at)
      last_run_at
    end
  end

  # Determine if we should recalculate next run
  def should_recalculate_next_run?
    cron_expression_changed? || timezone_changed? || is_active_changed?
  end

  # Recalculate and set the next run timestamp
  def recalculate_next_run
    return unless schedule_active?

    from_time = last_run_timestamp || Time.current
    set_next_run_timestamp(next_execution_time(from_time))
  end

  # Validate cron expression format
  def validate_cron_expression
    return if cron_expression.blank?

    cron = parse_cron_expression
    errors.add(:cron_expression, "is not a valid cron expression") unless cron
  rescue StandardError => e
    errors.add(:cron_expression, "is invalid: #{e.message}")
  end
end
