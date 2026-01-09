# frozen_string_literal: true

module Ai
  class WorkflowNodeExecution < ApplicationRecord
    self.table_name = "ai_workflow_node_executions"

    # Extracted concerns
    include Ai::WorkflowNodeExecution::StatusChecks
    include Ai::WorkflowNodeExecution::ExecutionControl
    include Ai::WorkflowNodeExecution::RetryManagement
    include Ai::WorkflowNodeExecution::Timing
    include Ai::WorkflowNodeExecution::DataManagement
    include Ai::WorkflowNodeExecution::NodeExecution
    include Ai::WorkflowNodeExecution::Logging
    include Ai::WorkflowNodeExecution::Broadcasting
    include Ai::WorkflowNodeExecution::RunProgress

    # Associations
    belongs_to :workflow_run, class_name: "Ai::WorkflowRun", foreign_key: "ai_workflow_run_id"
    belongs_to :node, class_name: "Ai::WorkflowNode", foreign_key: "ai_workflow_node_id"

    # Backward compatibility alias for MCP services
    alias_method :workflow_node, :node
    belongs_to :agent_execution, class_name: "Ai::AgentExecution", foreign_key: "ai_agent_execution_id", optional: true

    has_many :run_logs, class_name: "Ai::WorkflowRunLog",
             foreign_key: "ai_workflow_node_execution_id", dependent: :destroy
    has_many :approval_tokens, class_name: "Ai::WorkflowApprovalToken",
             foreign_key: "ai_workflow_node_execution_id", dependent: :destroy

    delegate :account, to: :workflow_run
    delegate :workflow, to: :workflow_run

    # Validations
    validates :execution_id, presence: true, uniqueness: true
    validates :node_id, presence: true
    validates :node_type, presence: true
    validates :status, presence: true, inclusion: {
      in: %w[pending running completed failed cancelled skipped waiting_approval],
      message: "must be a valid execution status"
    }
    validates :retry_count, numericality: { greater_than_or_equal_to: 0 }
    validates :max_retries, numericality: { greater_than_or_equal_to: 0 }
    validates :cost, numericality: { greater_than_or_equal_to: 0 }
    validate :validate_retry_limits

    # JSON columns
    attribute :input_data, :json, default: -> { {} }
    attribute :output_data, :json, default: -> { {} }
    attribute :configuration_snapshot, :json, default: -> { {} }
    attribute :error_details, :json, default: -> { {} }
    attribute :metadata, :json, default: -> { {} }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :skipped, -> { where(status: "skipped") }
    scope :waiting_approval, -> { where(status: "waiting_approval") }
    scope :active, -> { where(status: %w[pending running waiting_approval]) }
    scope :finished, -> { where(status: %w[completed failed cancelled skipped]) }
    scope :successful, -> { where(status: %w[completed skipped]) }
    scope :by_node_type, ->(type) { where(node_type: type) }
    scope :with_cost, -> { where("cost > 0") }
    scope :recent, -> { order(created_at: :desc) }

    # Callbacks
    before_validation :generate_execution_id, on: :create
    after_create :log_node_execution_started
    after_update :log_status_changes, if: :saved_change_to_status?
    after_update :calculate_duration, if: :saved_change_to_completed_at?

    private

    def generate_execution_id
      self.execution_id = SecureRandom.uuid if execution_id.blank?
    end

    def validate_retry_limits
      return unless retry_count.present? && max_retries.present?

      if retry_count > max_retries
        errors.add(:retry_count, "cannot exceed max_retries")
      end
    end

    def log_node_execution_started
      log_info("node_started", "Node execution started: #{node.name}", {
        "node_type" => node_type,
        "input_keys" => input_data.keys,
        "max_retries" => max_retries
      })
    end

    def log_status_changes
      old_status = saved_change_to_status[0]
      new_status = saved_change_to_status[1]

      event_type = case new_status
      when "running"
        "node_started"
      when "completed"
        "node_completed"
      when "failed"
        "node_failed"
      when "cancelled"
        "node_cancelled"
      when "skipped"
        "node_skipped"
      else
        "node_started"
      end

      log_info(event_type, "Node status changed from #{old_status} to #{new_status}", {
        "old_status" => old_status,
        "new_status" => new_status,
        "duration_ms" => execution_time_ms
      })
    end

    def calculate_duration
      return unless started_at && completed_at

      duration_seconds = completed_at - started_at
      calculated_duration_ms = [ duration_seconds * 1000, 0 ].max.to_i

      if duration_ms != calculated_duration_ms
        update_column(:duration_ms, calculated_duration_ms)
      end
    end

    def add_cost_to_run
      return unless saved_change_to_cost&.last.present?

      cost_added = saved_change_to_cost.last - (saved_change_to_cost.first || 0)
      return unless cost_added > 0

      add_cost_to_run_explicit(cost_added)
    end
  end
end
