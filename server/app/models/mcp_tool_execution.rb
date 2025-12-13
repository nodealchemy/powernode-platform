# frozen_string_literal: true

# McpToolExecution tracks individual executions of MCP tools
class McpToolExecution < ApplicationRecord
  # ==========================================
  # Concerns
  # ==========================================
  include Auditable

  # ==========================================
  # Associations
  # ==========================================
  belongs_to :mcp_tool
  belongs_to :user

  # ==========================================
  # Validations
  # ==========================================
  validates :status, inclusion: {
    in: %w[pending running completed failed cancelled],
    message: "must be a valid status"
  }

  validate :validate_parameters_format
  validate :validate_result_format

  # ==========================================
  # Scopes
  # ==========================================
  scope :pending, -> { where(status: "pending") }
  scope :running, -> { where(status: "running") }
  scope :completed, -> { where(status: "completed") }
  scope :failed, -> { where(status: "failed") }
  scope :for_tool, ->(tool_id) { where(mcp_tool_id: tool_id) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :recent, ->(duration = 24.hours) { where("created_at > ?", duration.ago) }
  scope :by_date, ->(date) { where("DATE(created_at) = ?", date) }

  # ==========================================
  # Callbacks
  # ==========================================
  before_validation :set_default_values, on: :create
  after_update :calculate_execution_time, if: :saved_change_to_status?
  after_update :broadcast_status_change, if: :saved_change_to_status?

  # ==========================================
  # Public Methods
  # ==========================================

  # Status check methods
  def pending?
    status == "pending"
  end

  def running?
    status == "running"
  end

  def completed?
    status == "completed"
  end

  def failed?
    status == "failed"
  end

  def cancelled?
    status == "cancelled"
  end

  # State transitions
  def start!
    update!(
      status: "running",
      started_at: Time.current
    )
  end

  def complete!(result_data)
    update!(
      status: "completed",
      result: result_data,
      completed_at: Time.current
    )
  end

  def fail!(error_msg)
    update!(
      status: "failed",
      error_message: error_msg,
      completed_at: Time.current
    )
  end

  def cancel!
    update!(
      status: "cancelled",
      error_message: "Execution cancelled by user",
      completed_at: Time.current
    )
  end

  # Get execution summary
  def summary
    {
      id: id,
      tool: mcp_tool.name,
      server: mcp_tool.mcp_server.name,
      status: status,
      parameters: parameters,
      result: result,
      error: error_message,
      duration_ms: duration_ms,
      created_at: created_at,
      started_at: started_at,
      completed_at: completed_at
    }
  end

  # ==========================================
  # Private Methods
  # ==========================================
  private

  def set_default_values
    self.status ||= "pending"
    self.parameters ||= {}
    self.result ||= {}
  end

  def validate_parameters_format
    return if parameters.blank?

    unless parameters.is_a?(Hash)
      errors.add(:parameters, "must be a hash")
    end
  end

  def validate_result_format
    return if result.blank?

    unless result.is_a?(Hash)
      errors.add(:result, "must be a hash")
    end
  end

  def calculate_execution_time
    return unless completed? || failed? || cancelled?
    return if execution_time_ms.present?

    if started_at && completed_at
      self.execution_time_ms = ((completed_at - started_at) * 1000).to_i
      save! if changed?
    elsif created_at && completed_at
      self.execution_time_ms = ((completed_at - created_at) * 1000).to_i
      save! if changed?
    end
  end

  def broadcast_status_change
    ActionCable.server.broadcast(
      "mcp_tool_execution_#{id}",
      {
        type: "status_update",
        execution_id: id,
        status: status,
        timestamp: Time.current.iso8601
      }
    )
  end
end
