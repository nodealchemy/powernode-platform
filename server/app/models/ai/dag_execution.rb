# frozen_string_literal: true

module Ai
  class DagExecution < ApplicationRecord
    # Concerns
    include Auditable

    # Constants
    STATUSES = %w[pending running completed failed cancelled].freeze

    # Associations
    belongs_to :account
    belongs_to :workflow, class_name: "Ai::Workflow", optional: true
    belongs_to :triggered_by, class_name: "User", optional: true

    has_many :a2a_tasks, class_name: "Ai::A2aTask", foreign_key: "dag_execution_id"

    # Validations
    validates :status, presence: true, inclusion: { in: STATUSES }
    validates :total_nodes, numericality: { greater_than_or_equal_to: 0 }
    validates :completed_nodes, numericality: { greater_than_or_equal_to: 0 }
    validates :failed_nodes, numericality: { greater_than_or_equal_to: 0 }

    # Scopes
    scope :pending, -> { where(status: "pending") }
    scope :running, -> { where(status: "running") }
    scope :completed, -> { where(status: "completed") }
    scope :failed, -> { where(status: "failed") }
    scope :cancelled, -> { where(status: "cancelled") }
    scope :active, -> { where(status: %w[pending running]) }
    scope :finished, -> { where(status: %w[completed failed cancelled]) }
    scope :resumable, -> { where(resumable: true, status: "failed") }
    scope :recent, -> { order(created_at: :desc) }

    # Status checks
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

    def finished?
      %w[completed failed cancelled].include?(status)
    end

    def active?
      %w[pending running].include?(status)
    end

    # Progress
    def progress_percentage
      return 0 if total_nodes.zero?

      ((completed_nodes.to_f / total_nodes) * 100).round(2)
    end

    def remaining_nodes
      total_nodes - completed_nodes - failed_nodes
    end

    # Node management
    def node_state(node_id)
      node_states[node_id]
    end

    def nodes_in_status(status)
      node_states.select { |_id, state| state["status"] == status }.keys
    end

    def completed_node_ids
      nodes_in_status("completed")
    end

    def failed_node_ids
      nodes_in_status("failed")
    end

    def skipped_node_ids
      nodes_in_status("skipped")
    end

    # Output access
    def node_output(node_id)
      final_outputs.dig(node_id, "output")
    end

    def all_outputs
      final_outputs.transform_values { |v| v["output"] }
    end

    # Summary
    def execution_summary
      {
        id: id,
        name: name,
        status: status,
        progress: progress_percentage,
        total_nodes: total_nodes,
        completed_nodes: completed_nodes,
        failed_nodes: failed_nodes,
        duration_ms: duration_ms,
        started_at: started_at,
        completed_at: completed_at,
        resumable: resumable,
        triggered_by: triggered_by&.full_name
      }
    end

    def execution_details
      execution_summary.merge(
        workflow_id: workflow_id,
        dag_definition: dag_definition,
        execution_plan: execution_plan,
        node_states: node_states,
        final_outputs: final_outputs,
        checkpoint_data: resumable ? checkpoint_data : nil,
        error_message: error_message,
        created_at: created_at
      )
    end
  end
end
