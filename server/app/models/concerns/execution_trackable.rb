# frozen_string_literal: true

# ExecutionTrackable concern for models that track execution status and timing
# Provides common execution behavior including status checks, lifecycle methods,
# and duration calculation.
#
# Required columns:
#   - status (string)
#   - started_at (datetime)
#   - completed_at (datetime)
#   - duration_ms or duration_seconds (integer, optional - calculated automatically)
#
# Example usage:
#   class MyExecution < ApplicationRecord
#     include ExecutionTrackable
#   end
#
module ExecutionTrackable
  extend ActiveSupport::Concern

  TERMINAL_STATUSES = %w[completed success failed failure cancelled skipped].freeze
  ACTIVE_STATUSES = %w[pending running waiting_approval].freeze

  included do
    # Scopes
    scope :pending_executions, -> { where(status: "pending") }
    scope :running_executions, -> { where(status: "running") }
    scope :completed_successfully, -> { where(status: %w[completed success]) }
    scope :failed_executions, -> { where(status: %w[failed failure]) }
    scope :terminal_executions, -> { where(status: TERMINAL_STATUSES) }
    scope :active_executions, -> { where(status: ACTIVE_STATUSES) }
    scope :by_execution_status, ->(status) { where(status: status) }

    # Callbacks
    after_update :calculate_execution_duration, if: :should_calculate_duration?
  end

  # ===========================================
  # Status Check Methods
  # ===========================================

  def pending?
    status == "pending"
  end

  def running?
    status == "running"
  end

  def completed?
    TERMINAL_STATUSES.include?(status)
  end

  def successful?
    %w[completed success].include?(status)
  end

  def failed?
    %w[failed failure].include?(status)
  end

  def cancelled?
    status == "cancelled"
  end

  def skipped?
    status == "skipped"
  end

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def waiting_approval?
    status == "waiting_approval"
  end

  # ===========================================
  # Lifecycle Methods
  # ===========================================

  # Start execution
  def start_execution!
    update!(
      status: "running",
      started_at: Time.current
    )
  end

  # Complete execution with a result status
  #
  # @param result_status [String] The final status ('completed', 'success', 'failed', 'failure')
  # @param options [Hash] Additional attributes to update (outputs, error_message, etc.)
  def complete_execution!(result_status, **options)
    attrs = {
      status: result_status,
      completed_at: Time.current
    }

    # Handle common optional attributes
    attrs[:outputs] = options[:outputs] if options.key?(:outputs) && respond_to?(:outputs=)
    attrs[:output_data] = options[:output_data] if options.key?(:output_data) && respond_to?(:output_data=)
    attrs[:error_message] = options[:error_message] if options.key?(:error_message) && respond_to?(:error_message=)
    attrs[:error_details] = options[:error_details] if options.key?(:error_details) && respond_to?(:error_details=)

    update!(attrs)
  end

  # Skip execution with optional reason
  #
  # @param reason [String, nil] Optional reason for skipping
  def skip_execution!(reason = nil)
    attrs = {
      status: "skipped",
      completed_at: Time.current
    }
    attrs[:error_message] = reason if reason && respond_to?(:error_message=)

    update!(attrs)
  end

  # Cancel execution with optional reason
  #
  # @param reason [String, nil] Optional reason for cancellation
  def cancel_execution!(reason = nil)
    attrs = {
      status: "cancelled",
      completed_at: Time.current
    }
    attrs[:cancelled_at] = Time.current if respond_to?(:cancelled_at=)
    attrs[:error_message] = reason if reason && respond_to?(:error_message=)

    update!(attrs)
  end

  # Fail execution with error details
  #
  # @param error_message [String] The error message
  # @param error_details [Hash] Additional error details
  def fail_execution!(error_message, error_details: {})
    attrs = {
      status: respond_to?(:failure_status) ? failure_status : "failed",
      completed_at: Time.current
    }
    attrs[:error_message] = error_message if respond_to?(:error_message=)
    attrs[:error_details] = error_details if respond_to?(:error_details=)

    update!(attrs)
  end

  # ===========================================
  # Timing Methods
  # ===========================================

  # Get execution duration in milliseconds
  #
  # @return [Integer, nil] Duration in milliseconds or nil if not calculable
  def execution_duration_ms
    return nil unless started_at && completed_at

    ((completed_at - started_at) * 1000).to_i
  end

  # Get execution duration in seconds
  #
  # @return [Integer, nil] Duration in seconds or nil if not calculable
  def execution_duration_seconds
    return nil unless started_at && completed_at

    (completed_at - started_at).to_i
  end

  # Get human-readable duration
  #
  # @return [String] Formatted duration string
  def formatted_duration
    duration = execution_duration_seconds
    return "N/A" unless duration

    if duration < 60
      "#{duration}s"
    elsif duration < 3600
      "#{duration / 60}m #{duration % 60}s"
    else
      hours = duration / 3600
      minutes = (duration % 3600) / 60
      "#{hours}h #{minutes}m"
    end
  end

  private

  # Check if duration should be calculated
  def should_calculate_duration?
    saved_change_to_completed_at? || (respond_to?(:completed_at_changed?) && completed_at_changed?)
  end

  # Calculate and store duration after completion
  def calculate_execution_duration
    return unless started_at.present? && completed_at.present?

    duration = [ (completed_at - started_at), 0 ].max

    if respond_to?(:duration_ms=)
      calculated_ms = (duration * 1000).to_i
      update_column(:duration_ms, calculated_ms) if duration_ms != calculated_ms
    elsif respond_to?(:duration_seconds=)
      calculated_seconds = duration.to_i
      update_column(:duration_seconds, calculated_seconds) if duration_seconds != calculated_seconds
    end
  end

  # Override in including model if a different failure status is needed
  def failure_status
    "failed"
  end
end
