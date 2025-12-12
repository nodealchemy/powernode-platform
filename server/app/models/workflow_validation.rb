# frozen_string_literal: true

# WorkflowValidation stores validation results for workflow health checks
class WorkflowValidation < ApplicationRecord
  # ==========================================
  # Concerns
  # ==========================================
  include Auditable

  # ==========================================
  # Associations
  # ==========================================
  belongs_to :workflow, class_name: "AiWorkflow", foreign_key: :workflow_id, optional: true

  # ==========================================
  # Validations
  # ==========================================
  validates :overall_status, presence: true, inclusion: {
    in: %w[valid invalid warning],
    message: "must be valid, invalid, or warning"
  }
  validates :health_score, presence: true, numericality: {
    greater_than_or_equal_to: 0,
    less_than_or_equal_to: 100
  }
  validates :total_nodes, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :validated_nodes, presence: true, numericality: { greater_than_or_equal_to: 0 }

  validate :validate_node_counts
  validate :validate_issues_format

  # ==========================================
  # Scopes
  # ==========================================
  scope :valid, -> { where(overall_status: "valid") }
  scope :invalid, -> { where(overall_status: "invalid") }
  scope :warnings, -> { where(overall_status: "warning") }
  scope :for_workflow, ->(workflow_id) { where(workflow_id: workflow_id) }
  scope :recent, ->(duration = 24.hours) { where("created_at > ?", duration.ago) }
  scope :healthy, -> { where("health_score >= ?", 80) }
  scope :unhealthy, -> { where("health_score < ?", 60) }
  scope :latest_for_each_workflow, -> {
    select("DISTINCT ON (workflow_id) *")
      .order("workflow_id, created_at DESC")
  }

  # ==========================================
  # Callbacks
  # ==========================================
  before_validation :set_default_values, on: :create
  before_save :calculate_health_score
  after_create :broadcast_validation_result

  # ==========================================
  # Public Methods
  # ==========================================

  # Status check methods
  def validation_valid?
    overall_status == "valid"
  end

  def validation_invalid?
    overall_status == "invalid"
  end

  def has_warnings?
    overall_status == "warning"
  end

  # Issue queries
  def error_issues
    issues.select { |issue| issue["severity"] == "error" }
  end

  def warning_issues
    issues.select { |issue| issue["severity"] == "warning" }
  end

  def info_issues
    issues.select { |issue| issue["severity"] == "info" }
  end

  # Count issues by severity
  def error_count
    error_issues.size
  end

  def warning_count
    warning_issues.size
  end

  def info_count
    info_issues.size
  end

  # Check if validation is stale
  def stale?(threshold = 1.hour)
    created_at < threshold.ago
  end

  # Get issues by category
  def issues_by_category(category)
    issues.select { |issue| issue["category"] == category }
  end

  # Check if specific issue exists
  def has_issue?(issue_code)
    issues.any? { |issue| issue["code"] == issue_code }
  end

  # Get auto-fixable issues
  def auto_fixable_issues
    issues.select { |issue| issue["auto_fixable"] == true }
  end

  # Generate summary
  def summary
    {
      workflow_id: workflow_id,
      overall_status: overall_status,
      health_score: health_score,
      total_nodes: total_nodes,
      validated_nodes: validated_nodes,
      issues: {
        errors: error_count,
        warnings: warning_count,
        info: info_count,
        total: issues.size
      },
      validation_duration_ms: validation_duration_ms,
      created_at: created_at
    }
  end

  # ==========================================
  # Private Methods
  # ==========================================
  private

  def set_default_values
    self.issues ||= []
    self.overall_status ||= "valid"
    self.health_score ||= 100
  end

  def validate_node_counts
    return if validated_nodes.nil? || total_nodes.nil?

    if validated_nodes > total_nodes
      errors.add(:validated_nodes, "cannot be greater than total nodes")
    end
  end

  def validate_issues_format
    return if issues.blank?

    unless issues.is_a?(Array)
      errors.add(:issues, "must be an array")
      return
    end

    issues.each_with_index do |issue, index|
      unless issue.is_a?(Hash)
        errors.add(:issues, "item at index #{index} must be a hash")
      end
    end
  end

  def calculate_health_score
    # Base score starts at 100
    score = 100

    # Deduct points for errors (severe impact)
    score -= error_count * 15

    # Deduct points for warnings (moderate impact)
    score -= warning_count * 5

    # Deduct points for incomplete validation
    if total_nodes > 0
      validation_completeness = (validated_nodes.to_f / total_nodes * 100)
      score -= (100 - validation_completeness) * 0.3
    end

    # Ensure score stays within bounds
    self.health_score = [ [ score, 0 ].max, 100 ].min.round
  end

  def broadcast_validation_result
    return unless workflow

    ActionCable.server.broadcast(
      "workflow_#{workflow_id}",
      {
        type: "validation_result",
        validation: summary
      }
    )
  end
end
