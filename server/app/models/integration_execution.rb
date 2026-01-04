# frozen_string_literal: true

class IntegrationExecution < ApplicationRecord
  # ==================== Concerns ====================
  include Auditable

  # ==================== Constants ====================
  STATUSES = %w[pending running completed failed cancelled].freeze
  TRIGGER_TYPES = %w[manual webhook scheduled workflow api].freeze

  # ==================== Associations ====================
  belongs_to :integration_instance
  belongs_to :account
  belongs_to :triggered_by_user, class_name: "User", optional: true
  belongs_to :parent_execution, class_name: "IntegrationExecution", optional: true

  has_many :retry_executions, class_name: "IntegrationExecution", foreign_key: :parent_execution_id, dependent: :nullify

  # ==================== Validations ====================
  validates :execution_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :trigger_type, inclusion: { in: TRIGGER_TYPES }, allow_nil: true
  validates :attempt_number, numericality: { greater_than: 0 }
  validates :max_attempts, numericality: { greater_than: 0 }

  # ==================== Scopes ====================
  scope :pending, -> { where(status: "pending") }
  scope :running, -> { where(status: "running") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :cancelled, -> { where(status: "cancelled") }
  scope :finished, -> { where(status: %w[completed failed cancelled]) }
  scope :retriable, -> { failed.where("attempt_number < max_attempts") }
  scope :by_trigger, ->(type) { where(trigger_type: type) }
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }

  # ==================== Callbacks ====================
  before_validation :generate_execution_id, on: :create
  before_save :sanitize_jsonb_fields
  after_update :update_instance_stats, if: :saved_change_to_status?

  # ==================== Instance Methods ====================

  def execution_summary
    {
      id: id,
      execution_id: execution_id,
      status: status,
      trigger_type: trigger_type,
      started_at: started_at,
      completed_at: completed_at,
      duration_ms: duration_ms,
      attempt_number: attempt_number
    }
  end

  def execution_details
    execution_summary.merge(
      input_data: input_data,
      output_data: output_data,
      error_details: error_details,
      trigger_source: trigger_source,
      trigger_metadata: trigger_metadata,
      max_attempts: max_attempts,
      next_retry_at: next_retry_at,
      parent_execution_id: parent_execution_id,
      resource_usage: resource_usage,
      cost_estimate: cost_estimate,
      integration_instance: integration_instance.instance_summary
    )
  end

  def start!
    update!(
      status: "running",
      started_at: Time.current
    )
  end

  def complete!(output = {})
    update!(
      status: "completed",
      completed_at: Time.current,
      duration_ms: calculate_duration,
      output_data: output
    )
  end

  def fail!(error_details_hash = {})
    updates = {
      status: "failed",
      completed_at: Time.current,
      duration_ms: calculate_duration,
      error_details: error_details_hash
    }

    if can_retry?
      updates[:next_retry_at] = calculate_next_retry_time
    end

    update!(updates)
  end

  def cancel!
    update!(
      status: "cancelled",
      completed_at: Time.current,
      duration_ms: calculate_duration
    )
  end

  def finished?
    %w[completed failed cancelled].include?(status)
  end

  def successful?
    status == "completed"
  end

  def can_retry?
    status == "failed" && attempt_number < max_attempts
  end

  def create_retry!
    return nil unless can_retry?

    IntegrationExecution.create!(
      integration_instance: integration_instance,
      account: account,
      triggered_by_user: triggered_by_user,
      parent_execution_id: id,
      input_data: input_data,
      trigger_type: trigger_type,
      trigger_source: trigger_source,
      trigger_metadata: trigger_metadata.merge("retry_of" => execution_id),
      attempt_number: attempt_number + 1,
      max_attempts: max_attempts
    )
  end

  def root_execution
    parent_execution&.root_execution || self
  end

  def all_attempts
    root = root_execution
    [root] + root.retry_executions.order(:attempt_number)
  end

  private

  def generate_execution_id
    return if execution_id.present?

    self.execution_id = "exec_#{SecureRandom.hex(12)}"
  end

  def sanitize_jsonb_fields
    self.input_data = {} if input_data.blank?
    self.output_data = {} if output_data.blank?
    self.error_details = {} if error_details.blank?
    self.trigger_metadata = {} if trigger_metadata.blank?
    self.resource_usage = {} if resource_usage.blank?
  end

  def calculate_duration
    return nil unless started_at.present?
    ((Time.current - started_at) * 1000).to_i
  end

  def calculate_next_retry_time
    # Exponential backoff: 2^attempt * 30 seconds
    delay_seconds = (2**attempt_number) * 30
    Time.current + delay_seconds.seconds
  end

  def update_instance_stats
    return unless finished?

    integration_instance.record_execution!(
      success: successful?,
      duration_ms: duration_ms,
      error: error_details&.dig("message")
    )

    # Increment template usage count on first successful execution
    if successful? && attempt_number == 1
      integration_instance.integration_template.increment_usage!
    end
  end
end
